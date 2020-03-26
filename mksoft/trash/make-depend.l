

(setq *make-depend-language-alist*
	  '(
		; C/C++
		(("*.c" "*.cc" "*.cpp" "*.cxx") "obj" "^#[ \t]*include[ \t]+\".*\""
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
	(dolist (d (split-string path "/" t))
	  (unless (equal d ".")
		(if (and (equal d "..")
				 (car st)
				 (not (equal (car st) "..")))
			(pop st)
		  (push d st))))
	(remove-trail-slash
	 (eval (cons #'concat
				 (mapcar (lambda (x) (concat x "/")) (reverse st)))))))



(defun make-depend (dir)
  (interactive "Dmake-depend: ")
  (let ((curbuf (selected-buffer))
		(tempbuf (create-new-buffer "*make-depend*"))
		depends
		cache
		)
	(set-buffer tempbuf)
	(cd dir)

	(dolist (l *make-depend-language-alist*)
	  (labels
		  ((rd-dep (file)	; read including files from `file'
			 (let ((c (assoc file cache :test #'equal))
				   (path (progn (string-match "\\(.*?\\)[^/]+$" file)
						   (string-replace-match file "\\1")))
				   lst)
			   (if c (cdr c)
				 (progn
				   (insert-file-contents file)
				   (goto-char 0)
				   (while (scan-buffer (car(cddr l)) :tail t :regexp t)
					 (dolist (i (funcall (cadr(cddr l))
										 (match-string 0)))
					   (push (calc-pathname
							  (concat path i))
							 lst)))
				   (erase-buffer tempbuf)
				   (setq lst (reverse lst))
				   (push (append (list file) lst) cache)
				   lst))))
		   (dep (lst rest)
			 (let ((f (pop rest)))
			   (if (eq f nil) lst	; rest is empty. fin.
				 (progn
				   (unless (member f lst :test #'equal)
					 (setq lst (append lst (list f)))
					 (setq rest (append (rd-dep f) rest)))
				   (dep lst rest)))))
		   (depend-files (file)
			 (dep nil (list file)))
		   )

		(let (files)
		  ;;listup files in the directory.
		  (setq files (append files (directory "." :wild (car l) :fileonly t)))
		  ;;enumerate dependency.
		  (dolist (f files)
			(push (append (list (progn
								  (string-match "\\(.*?\\)[^\\.]+$" f)
								  (string-replace-match f (concat "\\1" (cadr l)))))
						  (depend-files f))
				  depends)))))

	;; output to file.
	(insert (format-date-string "# %Y/%m/%d %H:%M:%S\n\n"))

	(dolist (d (reverse depends))
	  (insert (car d) ":")
	  (dolist (dd (cdr d)) (insert " " dd))
	  (insert "\n"))

	(write-region (point-min) (point-max)
				  *make-depend-output-file* nil)

	(set-buffer curbuf)
	(delete-buffer tempbuf)
	))
