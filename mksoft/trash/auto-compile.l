;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; auto-compile
;;    カレントディレクトリにMakefileがあるときはmake呼び出し
;;    無い時はコンパイラにファイル名を渡す
;;
;;--使い方--
;;[install]
;;  .xyzzyにコピペとかsite-lispに放り込んでrequireとか
;;  byte-compileすると動かなくなるので注意してください。
;;
;;[functions]
;;  (add-auto-compile-env name make cc env)
;;      設定を追加する
;;      name : 設定識別用シンボル
;;      make : makeプログラム
;;      cc   : コンパイラプログラム
;;      env  : 追加する環境変数の連想リスト
;;
;;  (change-auto-compile-env)
;;      設定を切り替える
;;
;;  (auto-compile)
;;      実行
;;
;;  (insert-to-circle 'symbol item)
;;      symbolに示される循環リストにitemを追加する（おまけ副産物）
;;
;;[使用例]
;;  (require "auto-compile")
;;  (add-auto-compile-env 'bcc "make" "bcc32" '(("path" . "C:\Borland\\bin")))
;;  (add-auto-compile-env 'mingw "mingw32-make" "gcc" '(("path" . "C:\\MinGW\\bin")))
;;  (add-auto-compile-env 'vctk "nmake" "cl"
;;  					  '(("path" . "C:\\Program Files\\Microsoft Visual C++ Toolkit 2003\\bin")
;;  						("include" . "C:\\Program Files\\Microsoft Visual C++ Toolkit 2003\\include;C:\\Program Files\\Microsoft SDK\\Include")
;;  						("lib" . "C:\\Program Files\\Microsoft Visual C++ Toolkit 2003\\lib;C:\\Program Files\\Microsoft SDK\\Lib;")))
;;
;;  (define-key ed::*c-mode-map* '(#\C-c #\C-c) 'auto-compile)
;;  (define-key ed::*c-mode-map* '(#\C-c #\C-t) 'change-auto-compile-env)
;;  (define-key ed::*c++-mode-map* '(#\C-c #\C-c) 'auto-compile)
;;  (define-key ed::*c++-mode-map* '(#\C-c #\C-t) 'change-auto-compile-env)
;;
;;--change log--
;;[2006]
;;  08/21 なぜかinsert-to-circleがbyte-compileできないけど動いてる。
;;        lambdaを再帰呼び出しとかやってるのが悪いのだろうか。
;;

(defun insert-to-circle (symbol item)
  (let ((clist (eval symbol)))
	(set symbol
		 (if (consp clist)
			 (setf (cdr ((lambda (f) (funcall f f clist))
						 (lambda (f a)
						   (cond ((eq (cdr a) clist) a)
								 ((eq (cdr a) nil) a)
								 (t (funcall f f (cdr a)))))))
				   (cons item clist))
		   (progn
			 (setf clist (list item))
			 (setf (cdr clist) clist))))))


(defvar *auto-compile-env-alist* nil)

(defun add-auto-compile-env (n m c e)
  (insert-to-circle
   '*auto-compile-env-alist*
   `(,n . ((make . ,m) (cc . ,c) (env . ,e)))))

(defun change-auto-compile-env ()
  (interactive)
  (if *auto-compile-env-alist*
	  (progn
		(setq *auto-compile-env-alist* (cdr *auto-compile-env-alist*))
		(message (concat "auto-compile-env: "
						 (symbol-name (caar *auto-compile-env-alist*)))))
	(message "*auto-compile-env-alist* is empty")))

(defun auto-compile ()
  (interactive)
  (if *auto-compile-env-alist*
	  (let ((ace (car *auto-compile-env-alist*))
			env  e)
		(dolist (temp (cdr (assoc 'env ace)))
		  (setf env (append env
							`((,(car temp) .
							   ,(concat (cdr temp) ";" (si:getenv (car temp))))))))
		(setq e (if (file-exist-p "Makefile")
					(cdr (assoc 'make ace))
				  (concat (cdr (assoc 'cc ace)) " \"" (get-buffer-file-name) "\"")))
		(message (concat "auto-compile: " e))
		(execute-subprocess e "" "*Command Output*" env))
	(message "*auto-compile-env-alist* is empty")))

