

(setq *make-depend-language-alist*
	  '(
		; C/C++
		(("\\.cc?" "\\.c\\(pp|xx\\)") "obj" "^#[ \t]*include[ \t]+\".*\""
		 (lambda (str) (list (cadr (split-string str "\"")))))
		; Assembly
		(("\\.asm") "obj" "^%?include[ \t]*\".+\""
		 (lambda (str) (list (cadr (split-string str "\"")))))
		; resource script
		(("\\.rc") "res" "^[ \t]*#[ \t]*include[ \t]*\".+\""
		 (lambda (str) (list (cadr (split-string str "\"")))))
		))

(setq *make-depend-output-file* "depend.mak")



(defun calc-pathname (path)
  (let (st)
	(dolist (d (split-string path "/"))
	  (unless (equal d ".")
		(if (and (equal d "..")
				 (car st)
				 (not (equal (car st) "..")))
			(pop st)
		  (push d st))))
	(combine-and-quote-strings (reverse st) "/")))



(defun make-depend (dir)
  (interactive "Dmake-depend: ")
  (let ((curbuf (current-buffer))
		(tempbuf (generate-new-buffer "*make-depend*"))
		depends
		cache
		)
	(set-buffer tempbuf)
	(cd dir)

	(dolist (l *make-depend-language-alist*)
	  (let
		  ((rd-dep (lambda (file)	; read including files from `file'
					 (let ((c (assoc file cache)) lst)
					   (if c (cdr c)
						 (progn
						   (insert-file-contents file)
						   (while (re-search-forward (car(cddr l)) nil t)
							 (dolist (i (funcall (cadr(cddr l))
												 (match-string-no-properties 0)))
							   (push (calc-pathname
									  (replace-regexp-in-string "[^/]+$" i file))
									 lst)))
						   (erase-buffer)
						   (setq lst (reverse lst))
						   (push (append (list file) lst) cache)
						   lst)))))
		   (dep (lambda (lst rest)
				  (let ((f (pop rest)))
					(if (eq f nil) lst	; rest is empty. fin.
					  (progn
						(unless (member f lst)
						  (setq lst (append lst (list f)))
						  (setq rest (append (funcall rd-dep f) rest)))
						(funcall dep lst rest))))))
		   (depend-files (lambda (file)
						   (funcall dep nil (list file))))
		   )

		(let (files)
		  ;;listup files in the directory.
		  (dolist (p (car l))
			(setq files (append files (directory-files "." nil p))))
		  ;;enumerate dependency.
		  (dolist (f files)
			(push (append (list (replace-regexp-in-string
								 "[^\\.]+$" (cadr l) f))
						  (funcall depend-files f))
				  depends)
			))))

  ;; output to file.
  (insert (format-time-string "# %Y/%m/%d %H:%M:%S\n\n"))
 
  (dolist (d (reverse depends))
	(insert (car d) ":")
	(dolist (dd (cdr d)) (insert " " dd))
	(insert "\n"))

  (write-region (point-min) (point-max)
				  *make-depend-output-file* nil)

  (set-buffer curbuf)
  (kill-buffer tempbuf)
  ))

