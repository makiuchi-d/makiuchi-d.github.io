;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; make-depend (������Ή���)
;;    �ˑ��֌W�𒲂ׁAMakefile�`���œf��
;;
;;--�g����--
;;[install]
;;  .xyzzy�ɃR�s�y�Ƃ�site-lisp�ɕ��荞���require�Ƃ�
;;[usage]
;;  M-x make-depend �ŌĂяo��
;;
;;--change log--
;;[2006]
;;  01/12: �Ƃ肠������������
;;  01/13: ������ւ̑Ή��Ƃ�
;;         �G���[�Œ��f�����Ƃ������̃f�B���N�g���ɖ߂�悤��
;;         language�̑����ǂ݂₷��
;;  01/14: �R���p�C����t�@�C�������}�N���ɓ������悤��
;;         ���K�\�����R���p�C������悤��
;;         ��͒��t�@�C������message�ŕ\��
;;         �t�@�C���̉�͂Ƀo�b�t�@���g���悤��
;;  01/15: 1���߂ŕ����t�@�C����include����悤�Ȍ���ɂ��Ή��ł���悤��
;;  01/17: C/C++�̊g���q��ǉ�
;;  01/20: �t�@�C�������o�֐���language���ł��炩���ߓW�J���Ă����悤��
;;
;;--memo--
;;  �֐�������Ȃ̂́A�ŏ���.xyzzy�Ƃ��ɃR�s�y�Ƃ��Ŏg�����肾��������B
;;  �ł�������Ƌ���ɂȂ�C���B�ǂ݂ɂ����B
;;  �������̂��Ƒ��ɂ��֐�,�萔�p�ӂ���Makefile���������܂ł��Ă݂�H
;;  �Ăяo���Ă�API���ׂĕK�v��*.lib���񋓂�����Ƃ��B
;;  �������ɂ����܂ł͂��C���Ȃ��̂ŁA�N���[
;;
(defun make-depend (dir)
  (interactive "DMake depend: ")
  (let ( ; �J�X�^�}�C�Y����Ƃ��͂��̕ӂ��e�L�g�[��
        (output-name "depend.mak")
        (depth 0)
        (language ; ������ɂ��Ή�������Ƃ��͂����ɒǉ�����΂����B
         `(; C/C++
           (("*.c" "*.cpp" "*.cxx" "*.cc") ("OBJ" . "obj") "^[ \t]*#[ \t]*include[ \t]*\".+\""
            ,#'(lambda (str) (list (second (split-string str "\"")))))
           ; assembly
           (("*.asm") ("OBJ" . "obj") "^%?include[ \t]*\".+\""
            ,#'(lambda (str) (list (second (split-string str "\"")))))
           ; resource
           (("*.rc") ("RES" . "res") "^[ \t]*#[ \t]*include[ \t]*\".+\""
            ,#'(lambda (str) (list (second (split-string str "\"")))))
           ))
        (msg_analyzing "Analyizing dependence ...")
        (msg_writing   "writing ...")
        (msg_finish    "make-depend ... done.")
        ; �����g�p�ϐ�
        files depends macros tempbuf curbuf
        name includes str path pattern stream)
    (labels
        ; language����l�����o���֐�����
        ((lang-wild-card (l) (car l))
         (lang-set-macro (l) (consp (cadr l)))
         (lang-macro-name (l) (caadr l))
         (lang-output-ext (l) (cdadr l))
         (lang-pattern (l) (caddr l))
         (lang-extract (l) (cadddr l))
         (func-exit() ; �I������
           (set-buffer curbuf) ; ���̃o�b�t�@�ɖ߂�
           (delete-buffer tempbuf)))

      (message msg_analyzing)

      ; ��Ɨp�o�b�t�@�쐬
      (setf curbuf (selected-buffer))
      (setf tempbuf (create-new-buffer "*make-depend*"))
      (set-buffer tempbuf)
      (set-default-directory dir) ; �f�B���N�g�����ړ�

      (handler-case ; ��������G���[�ߑ�
          (progn
            (dolist (l language) ; ���ꂼ��̌���ɑ΂���
              ; �Y���t�@�C�����
              (setf files (directory (default-directory)
                                     :wild (lang-wild-card l)
                                     :recursive t
                                     :depth (if (> 0 depth) 0 depth)
                                     :file-only t))
              ; �}�N�����X�g
              (when (lang-set-macro l)
                (setf m nil)
                ; �}�N�������������͒ǉ�
                (unless (assoc (lang-macro-name l) macros :test #'equal)
                  (setf macros (append macros `((,(lang-macro-name l))))))
                ; �o�̓t�@�C������ǉ�
                (dolist (s files)
                  (let ((ext (concat (pathname-type s) "$"))) ; �g���q
                    (setf name (substitute-string s ext (lang-output-ext l)))
                    (setf m (append m `(,name)))))
                (rplacd
                 (last (assoc (lang-macro-name l) macros :test #'string=)) m))

              ; �ˑ����
              (when (lang-pattern l) ; �p�^�[����nil�̎��͑������Ȃ�
                ; ���K�\�����R���p�C��
                (setf pattern (compile-regexp (lang-pattern l)))

                (while (setf name (first files)) ; �e�t�@�C���ɑ΂���
                  (setf files (rest files))
                  ; ���ɉ�͂��Ă����͂��Ȃ�
                  (unless (assoc name depends :test #'path-equal)
                    (message (format nil "~A ~A" msg_analyzing name))
                    (setf includes `(,name)) ; �擪�͉�͒��t�@�C��
                    (setf path (substitute-string ; path�����o��
                                name (concat (file-namestring name) "$") ""))
                    ; �t�@�C���̒�������
                    (insert-file-contents name) ; �t�@�C����ǂݍ���
                    (goto-char 0)
                    (while (scan-buffer pattern :tail t)
                      (setf str (match-string 0))
                      ; �t�@�C�������X�g���o
                      (setf str (funcall (lang-extract l) str))
                      (dolist (s str)
                        (setf s (concat path s)) ; �p�X�ǉ�
                        (nconc includes `(,s))))
                    (erase-buffer tempbuf) ; ��ƃo�b�t�@�N���A

                    ; ��͌��ʂɒǉ�
                    (setf depends (append depends `(,includes)))
                    ; include���Ă�t�@�C������͑҂��ɒǉ�
                    (setf files (append files (rest includes)))))))

            ; �����o��
            (message msg_writing)
            (with-open-file (out output-name :direction :output)
              ; ���t�Ƃ������o���Ă݂���
              (format-date out "# %y/%m/%d %H:%M:%S\n\n")
              ; �}�N��
              (dolist (m macros)
                (format out "~A =" (first m))
                (dolist (obj (rest m)) (format out " ~A" obj))
                (format out "~%"))
              (format out "~%")
              ; �ˑ��֌W
              (dolist (dep depends)
                (when (rest dep) ; �ˑ����ЂƂ������Ƃ��͏����o���Ȃ�
                  (format out "~A:" (first dep))
                  (dolist (dep (rest dep)) (format out " ~A" dep))
                  (format out "~%"))))

            (message msg_finish)) ; �G���[�ߑ������܂�

        (condition (c) ; �G���[��
          (func-exit)  ; �I���������������
          (error c)))  ; �R���f�B�V��������
      ; �I������
      (func-exit))))

