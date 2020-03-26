;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; make-depend (多言語対応版)
;;    依存関係を調べ、Makefile形式で吐く
;;
;;--使い方--
;;[install]
;;  .xyzzyにコピペとかsite-lispに放り込んでrequireとか
;;[usage]
;;  M-x make-depend で呼び出し
;;
;;--change log--
;;[2006]
;;  01/12: とりあえず動くもの
;;  01/13: 他言語への対応とか
;;         エラーで中断したときも元のディレクトリに戻るように
;;         languageの操作を読みやすく
;;  01/14: コンパイル後ファイル名をマクロに入れられるように
;;         正規表現をコンパイルするように
;;         解析中ファイル名をmessageで表示
;;         ファイルの解析にバッファを使うように
;;  01/15: 1命令で複数ファイルをincludeするような言語にも対応できるように
;;  01/17: C/C++の拡張子を追加
;;  01/20: ファイル名抽出関数をlanguage内であらかじめ展開しておくように
;;
;;--memo--
;;  関数一個だけなのは、最初は.xyzzyとかにコピペとかで使うつもりだったから。
;;  でもちょっと巨大になり気味。読みにくい。
;;  いっそのこと他にも関数,定数用意してMakefile自動生成までしてみる？
;;  呼び出してるAPI調べて必要な*.libも列挙したりとか。
;;  さすがにそこまではやる気がないので、誰かー
;;
(defun make-depend (dir)
  (interactive "DMake depend: ")
  (let ( ; カスタマイズするときはこの辺をテキトーに
        (output-name "depend.mak")
        (depth 0)
        (language ; 他言語にも対応させるときはここに追加すればおｋ。
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
        ; 内部使用変数
        files depends macros tempbuf curbuf
        name includes str path pattern stream)
    (labels
        ; languageから値を取り出す関数たち
        ((lang-wild-card (l) (car l))
         (lang-set-macro (l) (consp (cadr l)))
         (lang-macro-name (l) (caadr l))
         (lang-output-ext (l) (cdadr l))
         (lang-pattern (l) (caddr l))
         (lang-extract (l) (cadddr l))
         (func-exit() ; 終了処理
           (set-buffer curbuf) ; 元のバッファに戻る
           (delete-buffer tempbuf)))

      (message msg_analyzing)

      ; 作業用バッファ作成
      (setf curbuf (selected-buffer))
      (setf tempbuf (create-new-buffer "*make-depend*"))
      (set-buffer tempbuf)
      (set-default-directory dir) ; ディレクトリを移動

      (handler-case ; ここからエラー捕捉
          (progn
            (dolist (l language) ; それぞれの言語に対して
              ; 該当ファイルを列挙
              (setf files (directory (default-directory)
                                     :wild (lang-wild-card l)
                                     :recursive t
                                     :depth (if (> 0 depth) 0 depth)
                                     :file-only t))
              ; マクロリスト
              (when (lang-set-macro l)
                (setf m nil)
                ; マクロ名が無い時は追加
                (unless (assoc (lang-macro-name l) macros :test #'equal)
                  (setf macros (append macros `((,(lang-macro-name l))))))
                ; 出力ファイル名を追加
                (dolist (s files)
                  (let ((ext (concat (pathname-type s) "$"))) ; 拡張子
                    (setf name (substitute-string s ext (lang-output-ext l)))
                    (setf m (append m `(,name)))))
                (rplacd
                 (last (assoc (lang-macro-name l) macros :test #'string=)) m))

              ; 依存解析
              (when (lang-pattern l) ; パターンがnilの時は走査しない
                ; 正規表現をコンパイル
                (setf pattern (compile-regexp (lang-pattern l)))

                (while (setf name (first files)) ; 各ファイルに対して
                  (setf files (rest files))
                  ; 既に解析してたら解析しない
                  (unless (assoc name depends :test #'path-equal)
                    (message (format nil "~A ~A" msg_analyzing name))
                    (setf includes `(,name)) ; 先頭は解析中ファイル
                    (setf path (substitute-string ; pathを取り出す
                                name (concat (file-namestring name) "$") ""))
                    ; ファイルの中を検索
                    (insert-file-contents name) ; ファイルを読み込み
                    (goto-char 0)
                    (while (scan-buffer pattern :tail t)
                      (setf str (match-string 0))
                      ; ファイル名リスト抽出
                      (setf str (funcall (lang-extract l) str))
                      (dolist (s str)
                        (setf s (concat path s)) ; パス追加
                        (nconc includes `(,s))))
                    (erase-buffer tempbuf) ; 作業バッファクリア

                    ; 解析結果に追加
                    (setf depends (append depends `(,includes)))
                    ; includeしてるファイルを解析待ちに追加
                    (setf files (append files (rest includes)))))))

            ; 書き出し
            (message msg_writing)
            (with-open-file (out output-name :direction :output)
              ; 日付とか書き出してみたり
              (format-date out "# %y/%m/%d %H:%M:%S\n\n")
              ; マクロ
              (dolist (m macros)
                (format out "~A =" (first m))
                (dolist (obj (rest m)) (format out " ~A" obj))
                (format out "~%"))
              (format out "~%")
              ; 依存関係
              (dolist (dep depends)
                (when (rest dep) ; 依存がひとつも無いときは書き出さない
                  (format out "~A:" (first dep))
                  (dolist (dep (rest dep)) (format out " ~A" dep))
                  (format out "~%"))))

            (message msg_finish)) ; エラー捕捉ここまで

        (condition (c) ; エラー時
          (func-exit)  ; 終了処理をした後で
          (error c)))  ; コンディション放流
      ; 終了処理
      (func-exit))))


