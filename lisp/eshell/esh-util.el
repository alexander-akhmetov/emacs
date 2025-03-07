;;; esh-util.el --- general utilities  -*- lexical-binding:t -*-

;; Copyright (C) 1999-2022 Free Software Foundation, Inc.

;; Author: John Wiegley <johnw@gnu.org>

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(require 'seq)
(eval-when-compile (require 'cl-lib))

(defgroup eshell-util nil
  "This is general utility code, meant for use by Eshell itself."
  :tag "General utilities"
  :group 'eshell)

;;; User Variables:

(defcustom eshell-stringify-t t
  "If non-nil, the string representation of t is \"t\".
If nil, t will be represented only in the exit code of the function,
and not printed as a string.  This causes Lisp functions to behave
similarly to external commands, as far as successful result output."
  :type 'boolean)

(defcustom eshell-group-file "/etc/group"
  "If non-nil, the name of the group file on your system."
  :type '(choice (const :tag "No group file" nil) file))

(defcustom eshell-passwd-file "/etc/passwd"
  "If non-nil, the name of the passwd file on your system."
  :type '(choice (const :tag "No passwd file" nil) file))

(defcustom eshell-hosts-file "/etc/hosts"
  "The name of the /etc/hosts file.
Use `pcomplete-hosts-file' instead; this variable is obsolete and
has no effect."
  :type '(choice (const :tag "No hosts file" nil) file))
;; Don't make it into an alias, because it doesn't really work with
;; custom and risks creating duplicate entries.  Just point users to
;; the other variable, which is less frustrating.
(make-obsolete-variable 'eshell-hosts-file nil "28.1")

(defcustom eshell-handle-errors t
  "If non-nil, Eshell will handle errors itself.
Setting this to nil is offered as an aid to debugging only."
  :type 'boolean)

(defcustom eshell-private-file-modes #o600 ; umask 177
  "The file-modes value to use for creating \"private\" files."
  :type 'integer)

(defcustom eshell-private-directory-modes #o700 ; umask 077
  "The file-modes value to use for creating \"private\" directories."
  :type 'integer)

(defcustom eshell-tar-regexp
  "\\.t\\(ar\\(\\.\\(gz\\|bz2\\|xz\\|Z\\)\\)?\\|gz\\|a[zZ]\\|z2\\)\\'"
  "Regular expression used to match tar file names."
  :version "24.1"			; added xz
  :type 'regexp)

(defcustom eshell-convert-numeric-arguments t
  "If non-nil, converting arguments of numeric form to Lisp numbers.
Numeric form is tested using the regular expression
`eshell-number-regexp'.

NOTE: If you find that numeric conversions are interfering with the
specification of filenames (for example, in calling `find-file', or
some other Lisp function that deals with files, not numbers), add the
following in your init file:

  (put \\='find-file \\='eshell-no-numeric-conversions t)

Any function with the property `eshell-no-numeric-conversions' set to
a non-nil value, will be passed strings, not numbers, even when an
argument matches `eshell-number-regexp'."
  :type 'boolean)

(defcustom eshell-number-regexp "-?\\([0-9]*\\.\\)?[0-9]+\\(e[-0-9.]+\\)?"
  "Regular expression used to match numeric arguments.
If `eshell-convert-numeric-arguments' is non-nil, and an argument
matches this regexp, it will be converted to a Lisp number, using the
function `string-to-number'."
  :type 'regexp)

(defcustom eshell-ange-ls-uids nil
  "List of user/host/id strings, used to determine remote ownership."
  :type '(repeat (cons :tag "Host for User/UID map"
		       (string :tag "Hostname")
		       (repeat (cons :tag "User/UID List"
				     (string :tag "Username")
				     (repeat :tag "UIDs" string))))))

;;; Internal Variables:

(defvar eshell-group-names nil
  "A cache to hold the names of groups.")

(defvar eshell-group-timestamp nil
  "A timestamp of when the group file was read.")

(defvar eshell-user-names nil
  "A cache to hold the names of users.")

(defvar eshell-user-timestamp nil
  "A timestamp of when the user file was read.")

;;; Obsolete variables:

(define-obsolete-variable-alias 'eshell-host-names
  'pcomplete--host-name-cache "28.1")
(define-obsolete-variable-alias 'eshell-host-timestamp
  'pcomplete--host-name-cache-timestamp "28.1")
(defvar pcomplete--host-name-cache)
(defvar pcomplete--host-name-cache-timestamp)

;;; Functions:

(defsubst eshell-under-windows-p ()
  "Return non-nil if we are running under MS-DOS/Windows."
  (memq system-type '(ms-dos windows-nt)))

(defmacro eshell-condition-case (tag form &rest handlers)
  "If `eshell-handle-errors' is non-nil, this is `condition-case'.
Otherwise, evaluates FORM with no error handling."
  (declare (indent 2) (debug (sexp form &rest form)))
  (if eshell-handle-errors
      `(condition-case-unless-debug ,tag
	   ,form
	 ,@handlers)
    form))

(defun eshell-find-delimiter
  (open close &optional bound reverse-p backslash-p)
  "From point, find the CLOSE delimiter corresponding to OPEN.
The matching is bounded by BOUND. If REVERSE-P is non-nil,
process the region backwards.

If BACKSLASH-P is non-nil, or OPEN and CLOSE are different
characters, then a backslash can be used to escape a delimiter
(or another backslash).  Otherwise, the delimiter is escaped by
doubling it up."
  (save-excursion
    (let ((depth 1)
	  (bound (or bound (point-max))))
      (when (if reverse-p
                (eq (char-before) close)
              (eq (char-after) open))
        (forward-char (if reverse-p -1 1)))
      (while (and (> depth 0)
                  (funcall (if reverse-p #'> #'<) (point) bound))
        (let ((c (if reverse-p (char-before) (char-after))))
	  (cond ((and (not reverse-p)
		      (or (not (eq open close))
			  backslash-p)
		      (eq c ?\\)
                      (memq (char-after (1+ (point)))
                            (list open close ?\\)))
		 (forward-char 1))
		((and reverse-p
		      (or (not (eq open close))
			  backslash-p)
                      (eq (char-before (1- (point))) ?\\)
                      (memq c (list open close ?\\)))
		 (forward-char -1))
		((eq open close)
                 (when (eq c open)
                   (if (and (not backslash-p)
                            (eq (if reverse-p
                                    (char-before (1- (point)))
                                  (char-after (1+ (point))))
                                open))
                       (forward-char (if reverse-p -1 1))
                     (setq depth (1- depth)))))
		((= c open)
		 (setq depth (+ depth (if reverse-p -1 1))))
		((= c close)
		 (setq depth (+ depth (if reverse-p 1 -1))))))
	(forward-char (if reverse-p -1 1)))
      (when (= depth 0)
        (if reverse-p (point) (1- (point)))))))

(defun eshell-convertible-to-number-p (string)
  "Return non-nil if STRING can be converted to a number.
If `eshell-convert-numeric-aguments', always return nil."
  (and eshell-convert-numeric-arguments
       (string-match
        (concat "\\`\\s-*" eshell-number-regexp "\\s-*\\'")
        string)))

(defun eshell-convert-to-number (string)
  "Try to convert STRING to a number.
If STRING doesn't look like a number (or
`eshell-convert-numeric-aguments' is nil), just return STRING
unchanged."
  (if (eshell-convertible-to-number-p string)
      (string-to-number string)
    string))

(defun eshell-convert (string &optional to-string)
  "Convert STRING into a more-native Lisp object.
If TO-STRING is non-nil, always return a single string with
trailing newlines removed.  Otherwise, this behaves as follows:

* Return non-strings as-is.

* Split multiline strings by line.

* If `eshell-convert-numeric-aguments' is non-nil and every line
  of output looks like a number, convert them to numbers."
  (cond
   ((not (stringp string))
    (if to-string
        (eshell-stringify string)
      string))
   (to-string (string-trim-right string "\n+"))
   (t (let ((len (length string)))
        (if (= len 0)
	    string
	  (when (eq (aref string (1- len)) ?\n)
	    (setq string (substring string 0 (1- len))))
          (if (string-search "\n" string)
              (let ((lines (split-string string "\n")))
                (if (seq-every-p #'eshell-convertible-to-number-p lines)
                    (mapcar #'string-to-number lines)
                  lines))
            (eshell-convert-to-number string)))))))

(defvar-local eshell-path-env (getenv "PATH")
  "Content of $PATH.
It might be different from \(getenv \"PATH\"), when
`default-directory' points to a remote host.")

(make-obsolete-variable 'eshell-path-env 'eshell-get-path "29.1")

(defvar-local eshell-path-env-list nil)

(connection-local-set-profile-variables
 'eshell-connection-default-profile
 '((eshell-path-env-list . nil)))

(connection-local-set-profiles
 '(:application eshell)
 'eshell-connection-default-profile)

(defun eshell-get-path (&optional literal-p)
  "Return $PATH as a list.
If LITERAL-P is nil, return each directory of the path as a full,
possibly-remote file name; on MS-Windows, add the current
directory as the first directory in the path as well.

If LITERAL-P is non-nil, return the local part of each directory,
as the $PATH was actually specified."
  (with-connection-local-application-variables 'eshell
    (let ((remote (file-remote-p default-directory))
          (path
           (or eshell-path-env-list
               ;; If not already cached, get the path from
               ;; `exec-path', removing the last element, which is
               ;; `exec-directory'.
               (setq-connection-local eshell-path-env-list
                                      (butlast (exec-path))))))
      (when (and (not literal-p)
                 (not remote)
                 (eshell-under-windows-p))
        (push "." path))
      (if (and remote (not literal-p))
          (mapcar (lambda (x) (file-name-concat remote x)) path)
        path))))

(defun eshell-set-path (path)
  "Set the Eshell $PATH to PATH.
PATH can be either a list of directories or a string of
directories separated by `path-separator'."
  (with-connection-local-application-variables 'eshell
    (setq-connection-local
     eshell-path-env-list
     (if (listp path)
	 path
       ;; Don't use `parse-colon-path' here, since we don't want
       ;; the additional translations it does on each element.
       (split-string path (path-separator))))))

(defun eshell-parse-colon-path (path-env)
  "Split string with `parse-colon-path'.
Prepend remote identification of `default-directory', if any."
  (declare (obsolete nil "29.1"))
  (let ((remote (file-remote-p default-directory)))
    (if remote
	(mapcar
	 (lambda (x) (concat remote x))
	 (parse-colon-path path-env))
      (parse-colon-path path-env))))

(defun eshell-split-path (path)
  "Split a path into multiple subparts."
  (let ((len (length path))
	(i 0) (li 0)
	parts)
    (if (and (eshell-under-windows-p)
	     (> len 2)
	     (eq (aref path 0) ?/)
	     (eq (aref path 1) ?/))
	(setq i 2))
    (while (< i len)
      (if (and (eq (aref path i) ?/)
	       (not (get-text-property i 'escaped path)))
	  (setq parts (cons (if (= li i) "/"
			      (substring path li (1+ i))) parts)
		li (1+ i)))
      (setq i (1+ i)))
    (if (< li i)
	(setq parts (cons (substring path li i) parts)))
    (if (and (eshell-under-windows-p)
	     (string-match "\\`[A-Za-z]:\\'" (car (last parts))))
	(setcar (last parts) (concat (car (last parts)) "/")))
    (nreverse parts)))

(defun eshell-to-flat-string (value)
  "Make value a string.  If separated by newlines change them to spaces."
  (declare (obsolete nil "29.1"))
  (let ((text (eshell-stringify value)))
    (if (string-match "\n+\\'" text)
	(setq text (replace-match "" t t text)))
    (while (string-match "\n+" text)
      (setq text (replace-match " " t t text)))
    text))

(define-obsolete-function-alias 'eshell-flatten-list #'flatten-tree "27.1")

(defun eshell-stringify (object)
  "Convert OBJECT into a string value."
  (cond
   ((stringp object) object)
   ((numberp object)
    (number-to-string object))
   ((and (eq object t)
	 (not eshell-stringify-t))
    nil)
   (t
    (string-trim-right (pp-to-string object)))))

(defsubst eshell-stringify-list (args)
  "Convert each element of ARGS into a string value."
  (mapcar #'eshell-stringify args))

(defsubst eshell-list-to-string (list)
  "Convert LIST into a single string separated by spaces."
  (mapconcat #'eshell-stringify list " "))

(defsubst eshell-flatten-and-stringify (&rest args)
  "Flatten and stringify all of the ARGS into a single string."
  (eshell-list-to-string (flatten-tree args)))

(defsubst eshell-directory-files (regexp &optional directory)
  "Return a list of files in the given DIRECTORY matching REGEXP."
  (directory-files (or directory default-directory)
		   directory regexp))

(defun eshell-regexp-arg (prompt)
  "Return list of regexp and prefix arg using PROMPT."
  (let* (;; Don't clobber this.
	 (last-command last-command)
	 (regexp (read-from-minibuffer prompt nil nil nil
				       'minibuffer-history-search-history)))
    (list (if (string-equal regexp "")
	      (setcar minibuffer-history-search-history
		      (nth 1 minibuffer-history-search-history))
	    regexp)
	  (prefix-numeric-value current-prefix-arg))))

(defun eshell-printable-size (filesize &optional human-readable
				       block-size use-colors)
  "Return a printable FILESIZE."
  (let ((size (float (or filesize 0))))
    (if human-readable
	(if (< size human-readable)
	    (if (= (round size) 0)
		"0"
	      (if block-size
		  "1.0k"
		(format "%.0f" size)))
	  (setq size (/ size human-readable))
	  (if (< size human-readable)
	      (if (<= size 9.94)
		  (format "%.1fk" size)
		(format "%.0fk" size))
	    (setq size (/ size human-readable))
	    (if (< size human-readable)
		(let ((str (if (<= size 9.94)
			       (format "%.1fM" size)
			     (format "%.0fM" size))))
		  (if use-colors
		      (put-text-property 0 (length str)
					 'face 'bold str))
		  str)
	      (setq size (/ size human-readable))
	      (if (< size human-readable)
		  (let ((str (if (<= size 9.94)
				 (format "%.1fG" size)
			       (format "%.0fG" size))))
		    (if use-colors
			(put-text-property 0 (length str)
					   'face 'bold-italic str))
		    str)))))
      (if block-size
	  (setq size (/ size block-size)))
      (format "%.0f" size))))

(defun eshell-winnow-list (entries exclude &optional predicates)
  "Pare down the ENTRIES list using the EXCLUDE regexp, and PREDICATES.
The original list is not affected.  If the result is only one element
long, it will be returned itself, rather than returning a one-element
list."
  (let ((flist (list t))
	valid p listified)
    (unless (listp entries)
      (setq entries (list entries)
	    listified t))
    (dolist (entry entries)
      (unless (and exclude (string-match exclude entry))
	(setq p predicates valid (null p))
	(while p
	  (if (funcall (car p) entry)
	      (setq valid t)
	    (setq p nil valid nil))
	  (setq p (cdr p)))
	(when valid
	  (nconc flist (list entry)))))
    (if listified
	(cadr flist)
      (cdr flist))))

(defsubst eshell-redisplay ()
  "Allow Emacs to redisplay buffers."
  ;; for some strange reason, Emacs 21 is prone to trigger an
  ;; "args out of range" error in `sit-for', if this function
  ;; runs while point is in the minibuffer and the users attempt
  ;; to use completion.  Don't ask me.
  (condition-case nil
      (sit-for 0)
    (error nil)))

(defun eshell-read-passwd-file (file)
  "Return an alist correlating gids to group names in FILE."
  (let (names)
    (when (file-readable-p file)
      (with-temp-buffer
	(insert-file-contents file)
	(goto-char (point-min))
	(while (not (eobp))
	  (let* ((fields
		  (split-string (buffer-substring
				 (point) (progn (end-of-line)
						(point))) ":")))
	    (if (and (and fields (nth 0 fields) (nth 2 fields))
		     (not (assq (string-to-number (nth 2 fields)) names)))
		(setq names (cons (cons (string-to-number (nth 2 fields))
					(nth 0 fields))
				  names))))
	  (forward-line))))
    names))

(defun eshell-read-passwd (file result-var timestamp-var)
  "Read the contents of /etc/passwd for user names."
  (if (or (not (symbol-value result-var))
	  (not (symbol-value timestamp-var))
	  (time-less-p
	   (symbol-value timestamp-var)
	   (file-attribute-modification-time (file-attributes file))))
      (progn
	(set result-var (eshell-read-passwd-file file))
	(set timestamp-var (current-time))))
  (symbol-value result-var))

(defun eshell-read-group-names ()
  "Read the contents of /etc/group for group names."
  (if eshell-group-file
      (eshell-read-passwd eshell-group-file 'eshell-group-names
			  'eshell-group-timestamp)))

(defsubst eshell-group-id (name)
  "Return the user id for user NAME."
  (car (rassoc name (eshell-read-group-names))))

(defsubst eshell-group-name (gid)
  "Return the group name for the given GID."
  (cdr (assoc gid (eshell-read-group-names))))

(defun eshell-read-user-names ()
  "Read the contents of /etc/passwd for user names."
  (if eshell-passwd-file
      (eshell-read-passwd eshell-passwd-file 'eshell-user-names
			  'eshell-user-timestamp)))

(defsubst eshell-user-id (name)
  "Return the user id for user NAME."
  (car (rassoc name (eshell-read-user-names))))

(autoload 'pcomplete-read-hosts-file "pcomplete")
(autoload 'pcomplete-read-hosts "pcomplete")
(autoload 'pcomplete-read-host-names "pcomplete")
(define-obsolete-function-alias 'eshell-read-hosts-file
  #'pcomplete-read-hosts-file "28.1")
(define-obsolete-function-alias 'eshell-read-hosts
  #'pcomplete-read-hosts "28.1")
(define-obsolete-function-alias 'eshell-read-host-names
  #'pcomplete-read-host-names "28.1")

(defsubst eshell-copy-environment ()
  "Return an unrelated copy of `process-environment'."
  (mapcar #'concat process-environment))

(defun eshell-subgroups (groupsym)
  "Return all of the subgroups of GROUPSYM."
  (let ((subgroups (get groupsym 'custom-group))
	(subg (list t)))
    (while subgroups
      (if (eq (cadr (car subgroups)) 'custom-group)
	  (nconc subg (list (caar subgroups))))
      (setq subgroups (cdr subgroups)))
    (cdr subg)))

(defmacro eshell-with-file-modes (modes &rest forms)
  "Evaluate, with file-modes set to MODES, the given FORMS."
  (declare (obsolete with-file-modes "25.1"))
  `(with-file-modes ,modes ,@forms))

(defmacro eshell-with-private-file-modes (&rest forms)
  "Evaluate FORMS with private file modes set."
  `(with-file-modes ,eshell-private-file-modes ,@forms))

(defsubst eshell-make-private-directory (dir &optional parents)
  "Make DIR with file-modes set to `eshell-private-directory-modes'."
  (with-file-modes eshell-private-directory-modes
    (make-directory dir parents)))

(defsubst eshell-substring (string sublen)
  "Return the beginning of STRING, up to SUBLEN bytes."
  (if string
      (if (> (length string) sublen)
	  (substring string 0 sublen)
	string)))

(defun eshell-directory-files-and-attributes (dir &optional full match nosort id-format)
  "Make sure to use the handler for `directory-files-and-attributes'."
  (let* ((dir (expand-file-name dir)))
    (if (string-equal (file-remote-p dir 'method) "ftp")
	(let ((files (directory-files dir full match nosort)))
	  (mapcar
	   (lambda (file)
	     (cons file (eshell-file-attributes (expand-file-name file dir))))
	   files))
      (directory-files-and-attributes dir full match nosort id-format))))

(defun eshell-current-ange-uids ()
  (if (string-match "/\\([^@]+\\)@\\([^:]+\\):" default-directory)
      (let* ((host (match-string 2 default-directory))
	     (user (match-string 1 default-directory))
	     (host-users (assoc host eshell-ange-ls-uids)))
	(when host-users
	  (setq host-users (cdr host-users))
	  (cdr (assoc user host-users))))))

(autoload 'parse-time-string "parse-time")

(eval-when-compile
  (require 'ange-ftp))		; ange-ftp-parse-filename

(defvar tramp-file-name-structure)
(declare-function ange-ftp-ls "ange-ftp"
		  (file lsargs parse &optional no-error wildcard))
(declare-function ange-ftp-file-modtime "ange-ftp" (file))

(defun eshell-parse-ange-ls (dir)
  (require 'ange-ftp)
  (require 'tramp)
  (let ((ange-ftp-name-format
	 (list (nth 0 tramp-file-name-structure)
	       (nth 3 tramp-file-name-structure)
	       (nth 2 tramp-file-name-structure)
	       (nth 4 tramp-file-name-structure)))
	;; ange-ftp uses `ange-ftp-ftp-name-arg' and `ange-ftp-ftp-name-res'
	;; for optimization in `ange-ftp-ftp-name'. If Tramp wasn't active,
	;; there could be incorrect values from previous calls in case the
	;; "ftp" method is used in the Tramp file name. So we unset
	;; those values.
	(ange-ftp-ftp-name-arg "")
	(ange-ftp-ftp-name-res nil)
	entry)
    (with-temp-buffer
      (insert (ange-ftp-ls dir "-la" nil))
      (goto-char (point-min))
      (if (looking-at "^total [0-9]+$")
	  (forward-line 1))
      ;; Some systems put in a blank line here.
      (if (eolp) (forward-line 1))
      (while (looking-at
	      `,(concat "\\([dlscb-][rwxst-]+\\)"
			"\\s-*" "\\([0-9]+\\)" "\\s-+"
			"\\(\\S-+\\)" "\\s-+"
			"\\(\\S-+\\)" "\\s-+"
			"\\([0-9]+\\)" "\\s-+" "\\(.*\\)"))
	(let* ((perms (match-string 1))
	       (links (string-to-number (match-string 2)))
	       (user (match-string 3))
	       (group (match-string 4))
	       (size (string-to-number (match-string 5)))
	       (name (ange-ftp-parse-filename))
	       (mtime
		(let ((moment (parse-time-string (match-string 6))))
		  (if (decoded-time-second moment)
		      (setf (decoded-time-year moment)
			    (decoded-time-year (decode-time)))
		    (setf (decoded-time-second moment) 0)
		    (setf (decoded-time-minute moment) 0)
                    (setf (decoded-time-hour moment) 0))
		  (encode-time moment)))
	       symlink)
	  (if (string-match "\\(.+\\) -> \\(.+\\)" name)
	      (setq symlink (match-string 2 name)
		    name (match-string 1 name)))
	  (setq entry
		(cons
		 (cons name
		       (list (if (eq (aref perms 0) ?d)
				 t
			       symlink)
			     links user group
			     nil mtime nil
			     size perms nil nil)) entry)))
	(forward-line)))
    entry))

(defun eshell-file-attributes (file &optional id-format)
  "Return the attributes of FILE, playing tricks if it's over ange-ftp.
The optional argument ID-FORMAT specifies the preferred uid and
gid format.  Valid values are `string' and `integer', defaulting to
`integer'.  See `file-attributes'."
  (let* ((expanded-file (expand-file-name file))
	 entry)
    (if (string-equal (file-remote-p expanded-file 'method) "ftp")
	(let ((base (file-name-nondirectory expanded-file))
	      (dir (file-name-directory expanded-file)))
	  (if (string-equal "" base) (setq base "."))
	  (unless entry
	    (setq entry (eshell-parse-ange-ls dir))
	    (if entry
		(let ((fentry (assoc base (cdr entry))))
		  (if fentry
		      (setq entry (cdr fentry))
		    (setq entry nil)))))
	  entry)
      (file-attributes file id-format))))

(defsubst eshell-processp (proc)
  "If the `processp' function does not exist, PROC is not a process."
  (and (fboundp 'processp) (processp proc)))

(defun eshell-process-pair-p (procs)
  "Return non-nil if PROCS is a pair of process objects."
  (and (consp procs)
       (eshell-processp (car procs))
       (eshell-processp (cdr procs))))

(defun eshell-make-process-pair (procs)
  "Make a pair of process objects from PROCS if possible.
This represents the head and tail of a pipeline of processes,
where the head and tail may be the same process."
  (pcase procs
    ((pred eshell-processp) (cons procs procs))
    ((pred eshell-process-pair-p) procs)))

;; (defun eshell-copy-file
;;   (file newname &optional ok-if-already-exists keep-date)
;;   "Copy FILE to NEWNAME.  See docs for `copy-file'."
;;   (let (copied)
;;     (if (string-match "\\`\\([^:]+\\):\\(.*\\)" file)
;;	(let ((front (match-string 1 file))
;;	      (back (match-string 2 file))
;;	      buffer)
;;	  (if (and front (string-match eshell-tar-regexp front)
;;		     (setq buffer (find-file-noselect front)))
;;	    (with-current-buffer buffer
;;	      (goto-char (point-min))
;;	      (if (re-search-forward (concat " " (regexp-quote back)
;;					     "$") nil t)
;;		  (progn
;;		    (tar-copy (if (file-directory-p newname)
;;				  (expand-file-name
;;				   (file-name-nondirectory back) newname)
;;				newname))
;;		    (setq copied t))
;;		(error "%s not found in tar file %s" back front))))))
;;     (unless copied
;;       (copy-file file newname ok-if-already-exists keep-date))))

;; (defun eshell-file-attributes (filename)
;;   "Return a list of attributes of file FILENAME.
;; See the documentation for `file-attributes'."
;;   (let (result)
;;     (when (string-match "\\`\\([^:]+\\):\\(.*\\)\\'" filename)
;;       (let ((front (match-string 1 filename))
;;	    (back (match-string 2 filename))
;;	    buffer)
;;	(when (and front (string-match eshell-tar-regexp front)
;;		   (setq buffer (find-file-noselect front)))
;;	  (with-current-buffer buffer
;;	    (goto-char (point-min))
;;	    (when (re-search-forward (concat " " (regexp-quote back)
;;					     "\\s-*$") nil t)
;;	      (let* ((descrip (tar-current-descriptor))
;;		     (tokens (tar-desc-tokens descrip)))
;;		(setq result
;;		      (list
;;		       (cond
;;			((eq (tar-header-link-type tokens) 5)
;;			 t)
;;			((eq (tar-header-link-type tokens) t)
;;			 (tar-header-link-name tokens)))
;;		       1
;;		       (tar-header-uid tokens)
;;		       (tar-header-gid tokens)
;;		       (tar-header-date tokens)
;;		       (tar-header-date tokens)
;;		       (tar-header-date tokens)
;;		       (tar-header-size tokens)
;;		       (file-modes-number-to-symbolic
;;                       (logior (tar-header-mode tokens)
;;			        (cond
;;			         ((eq (tar-header-link-type tokens) 5) 16384)
;;			         ((eq (tar-header-link-type tokens) t) 32768))))
;;		       nil nil nil))))))))
;;     (or result
;;	(file-attributes filename))))

;; Obsolete.

(define-obsolete-function-alias 'eshell-uniquify-list #'seq-uniq "28.1")
(define-obsolete-function-alias 'eshell-uniqify-list #'seq-uniq "28.1")
(define-obsolete-function-alias 'eshell-copy-tree #'copy-tree "28.1")
(define-obsolete-function-alias 'eshell-user-name #'user-login-name "28.1")

(defun eshell-sublist (l &optional n m)
  "Return from LIST the N to M elements.
If N or M is nil, it means the end of the list."
  (declare (obsolete seq-subseq "28.1"))
  (seq-subseq l n (1+ m)))

(provide 'esh-util)

;;; esh-util.el ends here
