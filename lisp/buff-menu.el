;;; buff-menu.el --- Interface for viewing and manipulating buffers -*- lexical-binding: t -*-

;; Copyright (C) 1985-2022 Free Software Foundation, Inc.

;; Maintainer: emacs-devel@gnu.org
;; Keywords: convenience
;; Package: emacs

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

;; The Buffer Menu is used to view, edit, delete, or change attributes
;; of buffers.  The entry points are `C-x C-b' (`list-buffers') and
;; `M-x buffer-menu'.

;;; Code:

(require 'tabulated-list)

(defgroup Buffer-menu nil
  "Show a menu of all buffers in a buffer."
  :group 'tools
  :group 'convenience)

(defvar Buffer-menu-marker-char ?>
  "The mark character for marked buffers.")

(defvar Buffer-menu-del-char ?D
  "Character used to flag buffers for deletion.")

(defcustom Buffer-menu-use-header-line t
  "If non-nil, use the header line to display Buffer Menu column titles."
  :type 'boolean
  :group 'Buffer-menu)

(defface buffer-menu-buffer
  '((t (:weight bold)))
  "Face for buffer names in the Buffer Menu."
  :group 'Buffer-menu)
(put 'Buffer-menu-buffer 'face-alias 'buffer-menu-buffer)

(defun Buffer-menu--dynamic-name-width (buffers)
  "Return a name column width based on the current window width.
The width will never exceed the actual width of the buffer names,
but will never be narrower than 19 characters."
  (max 19
       ;; This gives 19 on an 80 column window, and take up
       ;; proportionally more space as the window widens.
       (min (truncate (/ (window-width) 4.2))
            (apply #'max 0 (mapcar (lambda (b)
                                     (length (buffer-name b)))
                                   buffers)))))

(defcustom Buffer-menu-name-width #'Buffer-menu--dynamic-name-width
  "Width of buffer name column in the Buffer Menu.
This can either be a number (used directly) or a function that
will be called with the list of buffers and should return a
number."
  :type '(choice function number)
  :group 'Buffer-menu
  :version "28.1")

(defcustom Buffer-menu-size-width 7
  "Width of buffer size column in the Buffer Menu."
  :type 'natnum
  :group 'Buffer-menu
  :version "24.3")

(defcustom Buffer-menu-mode-width 16
  "Width of mode name column in the Buffer Menu."
  :type 'natnum
  :group 'Buffer-menu)

(defcustom Buffer-menu-use-frame-buffer-list t
  "If non-nil, the Buffer Menu uses the selected frame's buffer list.
Buffers that were never selected in that frame are listed at the end.
If the value is nil, the Buffer Menu uses the global buffer list.
This variable matters if the Buffer Menu is sorted by visited order,
as it is by default."
  :type 'boolean
  :group 'Buffer-menu
  :version "22.1")

(defvar-local Buffer-menu-files-only nil
  "Non-nil if the current Buffer Menu lists only file buffers.
This is set by the prefix argument to `buffer-menu' and related
commands.")

(defvar-local Buffer-menu-filter-predicate nil
  "Function to filter out buffers in the buffer list.
Buffers that don't satisfy the predicate will be skipped.
The value should be a function of one argument; it will be
called with the buffer.  If this function returns non-nil,
then the buffer will be displayed in the buffer list.")

(defvar-local Buffer-menu-buffer-list nil
  "The current list of buffers or function to return buffers.")

(defvar-keymap Buffer-menu-mode-map
  :doc "Local keymap for `Buffer-menu-mode' buffers."
  :parent tabulated-list-mode-map
  "v"           #'Buffer-menu-select
  "2"           #'Buffer-menu-2-window
  "1"           #'Buffer-menu-1-window
  "f"           #'Buffer-menu-this-window
  "e"           #'Buffer-menu-this-window
  "C-m"         #'Buffer-menu-this-window
  "o"           #'Buffer-menu-other-window
  "C-o"         #'Buffer-menu-switch-other-window
  "s"           #'Buffer-menu-save
  "d"           #'Buffer-menu-delete
  "k"           #'Buffer-menu-delete
  "C-k"         #'Buffer-menu-delete
  "C-d"         #'Buffer-menu-delete-backwards
  "x"           #'Buffer-menu-execute
  "SPC"         #'next-line
  "DEL"         #'Buffer-menu-backup-unmark
  "~"           #'Buffer-menu-not-modified
  "u"           #'Buffer-menu-unmark
  "M-DEL"       #'Buffer-menu-unmark-all-buffers
  "U"           #'Buffer-menu-unmark-all
  "m"           #'Buffer-menu-mark
  "t"           #'Buffer-menu-visit-tags-table
  "%"           #'Buffer-menu-toggle-read-only
  "b"           #'Buffer-menu-bury
  "V"           #'Buffer-menu-view
  "O"           #'Buffer-menu-view-other-window
  "T"           #'Buffer-menu-toggle-files-only
  "M-s a C-s"   #'Buffer-menu-isearch-buffers
  "M-s a C-M-s" #'Buffer-menu-isearch-buffers-regexp
  "M-s a C-o"   #'Buffer-menu-multi-occur
  "<mouse-2>"     #'Buffer-menu-mouse-select
  "<follow-link>" 'mouse-face)

(put 'Buffer-menu-delete :advertised-binding "d")
(put 'Buffer-menu-this-window :advertised-binding "f")

(easy-menu-define Buffer-menu-mode-menu Buffer-menu-mode-map
  "Menu for `Buffer-menu-mode' buffers."
  '("Buffer-Menu"
    ["Mark" Buffer-menu-mark
     :help "Mark buffer on this line for being displayed by v command"]
    ["Unmark all" Buffer-menu-unmark-all
     :help "Cancel all requested operations on buffers"]
    ["Remove marks..." Buffer-menu-unmark-all-buffers
     :help "Cancel a requested operation on all buffers"]
    ["Unmark" Buffer-menu-unmark
     :help "Cancel all requested operations on buffer on this line and move down"]
    ["Mark for Save" Buffer-menu-save
     :help "Mark buffer on this line to be saved by x command"]
    ["Mark for Delete" Buffer-menu-delete
     :help "Mark buffer on this line to be deleted by x command"]
    ["Mark for Delete and Move Backwards" Buffer-menu-delete-backwards
     :help "Mark buffer on this line to be deleted by x command and move up one line"]
    "---"
    ["Execute" Buffer-menu-execute
     :help "Save and/or delete buffers marked with s or k commands"]
    ["Set Unmodified" Buffer-menu-not-modified
     :help "Mark buffer on this line as unmodified (no changes to save)"]
    ["Bury" Buffer-menu-bury
     :help "Bury the buffer listed on this line"]
    "---"
    ["Multi Occur Marked Buffers..." Buffer-menu-multi-occur
     :help "Show lines matching a regexp in marked buffers using Occur"]
    ["Isearch Marked Buffers..." Buffer-menu-isearch-buffers
     :help "Search for a string through all marked buffers using Isearch"]
    ["Regexp Isearch Marked Buffers..." Buffer-menu-isearch-buffers-regexp
     :help "Search for a regexp through all marked buffers using Isearch"]
    "---"
    ;; FIXME: The "Select" entries could use better names...
    ["Select in Current Window" Buffer-menu-this-window
     :help "Select this line's buffer in this window"]
    ["Select in Other Window" Buffer-menu-other-window
     :help "Select this line's buffer in other window, leaving buffer menu visible"]
    ["Select Current" Buffer-menu-1-window
     :help "Select this line's buffer, alone, in full frame"]
    ["Select Two" Buffer-menu-2-window
     :help "Select this line's buffer, with previous buffer in second window"]
    ["Select Marked" Buffer-menu-select
     :help "Select this line's buffer; also display buffers marked with `>'"]
    "---"
    ["Show Only File Buffers" Buffer-menu-toggle-files-only
     :help "Toggle whether the current buffer-menu displays only file buffers"
     :style toggle
     :selected Buffer-menu-files-only]
    "---"
    ["Refresh" revert-buffer
     :help "Refresh the *Buffer List* buffer contents"]
    ["Quit" quit-window
     :help "Remove the buffer menu from the display"]))

(define-derived-mode Buffer-menu-mode tabulated-list-mode "Buffer Menu"
  "Major mode for Buffer Menu buffers.
The Buffer Menu is invoked by the commands \\[list-buffers],
\\[buffer-menu], and \\[buffer-menu-other-window].
See `buffer-menu' for a description of its contents.

In Buffer Menu mode, the following commands are defined:
\\<Buffer-menu-mode-map>
\\[quit-window]    Remove the Buffer Menu from the display.
\\[Buffer-menu-this-window]    Select current line's buffer in place of the buffer menu.
\\[Buffer-menu-other-window]    Select that buffer in another window,
     so the Buffer Menu remains visible in its window.
\\[Buffer-menu-view]    Select current line's buffer, in `view-mode'.
\\[Buffer-menu-view-other-window]    Select that buffer in another window, in `view-mode'.
\\[Buffer-menu-switch-other-window]  Make another window display that buffer.
\\[Buffer-menu-mark]    Mark current line's buffer to be displayed.
\\[Buffer-menu-select]    Select current line's buffer.
     Also show buffers marked with \"m\", in other windows.
\\[Buffer-menu-1-window]    Select that buffer in full-frame window.
\\[Buffer-menu-2-window]    Select that buffer in one window, together with the
     buffer selected before this one in another window.
\\[Buffer-menu-isearch-buffers]    Incremental search in the marked buffers.
\\[Buffer-menu-isearch-buffers-regexp]  Isearch for regexp in the marked buffers.
\\[Buffer-menu-multi-occur]    Show lines matching regexp in the marked buffers.
\\[Buffer-menu-visit-tags-table]    `visit-tags-table' this buffer.
\\[Buffer-menu-not-modified]    Clear modified-flag on that buffer.
\\[Buffer-menu-save]    Mark that buffer to be saved, and move down.
\\[Buffer-menu-delete]    Mark that buffer to be deleted, and move down.
\\[Buffer-menu-delete-backwards]  Mark that buffer to be deleted, and move up.
\\[Buffer-menu-execute]    Delete or save marked buffers.
\\[Buffer-menu-unmark]    Remove all marks from current line.
     With prefix argument, also move up one line.
\\[Buffer-menu-unmark-all-buffers]    Remove a particular mark from all lines.
\\[Buffer-menu-unmark-all]    Remove all marks from all lines.
\\[Buffer-menu-backup-unmark]  Back up a line and remove marks.
\\[Buffer-menu-toggle-read-only]    Toggle read-only status of buffer on this line.
\\[revert-buffer]    Update the list of buffers.
\\[Buffer-menu-toggle-files-only]    Toggle whether the menu displays only file buffers.
\\[Buffer-menu-bury]    Bury the buffer listed on this line."
  :interactive nil
  (setq-local buffer-stale-function
              (lambda (&optional _noconfirm) 'fast))
  (add-hook 'tabulated-list-revert-hook 'list-buffers--refresh nil t))

(defun buffer-menu--display-help ()
  (message "%s"
           (substitute-command-keys
            (concat
             "Commands: "
             "\\<Buffer-menu-mode-map>"
             "\\[Buffer-menu-delete], "
             "\\[Buffer-menu-save], "
             "\\[Buffer-menu-execute], "
             "\\[Buffer-menu-unmark]; "
             "\\[Buffer-menu-this-window], "
             "\\[Buffer-menu-other-window], "
             "\\[Buffer-menu-1-window], "
             "\\[Buffer-menu-2-window], "
             "\\[Buffer-menu-mark], "
             "\\[Buffer-menu-select]; "
             "\\[Buffer-menu-not-modified], "
             "\\[Buffer-menu-toggle-read-only]; "
             "\\[quit-window] to quit; \\[describe-mode] for help"))))

(defun buffer-menu (&optional arg)
  "Switch to the Buffer Menu.
By default, the Buffer Menu lists all buffers except those whose
names start with a space (which are for internal use).  With
prefix argument ARG, show only buffers that are visiting files.

In the Buffer Menu, the first column (denoted \"C\") shows \".\"
for the buffer from which you came, \">\" for buffers you mark to
be displayed, and \"D\" for those you mark for deletion.

The \"R\" column has a \"%\" if the buffer is read-only.
The \"M\" column has a \"*\" if it is modified, or \"S\" if you
have marked it for saving.

The remaining columns show the buffer name, the buffer size in
characters, its major mode, and the visited file name (if any).

See `Buffer-menu-mode' for the keybindings available the Buffer
Menu.

The width of the various columns can be customized by changing
the `Buffer-menu-name-width', `Buffer-menu-size-width' and
`Buffer-menu-mode-width' variables."
  (interactive "P")
  (switch-to-buffer (list-buffers-noselect arg))
  (buffer-menu--display-help))

(defun buffer-menu-other-window (&optional arg)
  "Display the Buffer Menu in another window.
See `buffer-menu' for a description of the Buffer Menu.

By default, all buffers are listed except those whose names start
with a space (which are for internal use).  With prefix argument
ARG, show only buffers that are visiting files."
  (interactive "P")
  (switch-to-buffer-other-window (list-buffers-noselect arg))
  (buffer-menu--display-help))

;;;###autoload
(defun list-buffers (&optional arg)
  "Display a list of existing buffers.
The list is displayed in a buffer named \"*Buffer List*\".
See `buffer-menu' for a description of the Buffer Menu.

By default, all buffers are listed except those whose names start
with a space (which are for internal use).  With prefix argument
ARG, show only buffers that are visiting files."
  (interactive "P")
  (display-buffer (list-buffers-noselect arg)))

(defun Buffer-menu-toggle-files-only (arg)
  "Toggle whether the current `buffer-menu' displays only file buffers.
With a positive ARG, display only file buffers.  With zero or
negative ARG, display other buffers as well."
  (interactive "P" Buffer-menu-mode)
  (setq Buffer-menu-files-only
	(cond ((not arg) (not Buffer-menu-files-only))
	      ((> (prefix-numeric-value arg) 0) t)))
  (message (if Buffer-menu-files-only
	       "Showing only file-visiting buffers."
	     "Showing all non-internal buffers."))
  (revert-buffer))

(define-obsolete-function-alias 'Buffer-menu-sort 'tabulated-list-sort
  "28.1")


(defun Buffer-menu-buffer (&optional error-if-non-existent-p)
  "Return the buffer described by the current Buffer Menu line.
If there is no buffer here, return nil if ERROR-IF-NON-EXISTENT-P
is nil or omitted, and signal an error otherwise."
  (let ((buffer (tabulated-list-get-id)))
    (cond ((null buffer)
	   (if error-if-non-existent-p
	       (error "No buffer on this line")))
	  ((not (buffer-live-p buffer))
	   (if error-if-non-existent-p
	       (error "This buffer has been killed")))
	  (t buffer))))

(defun Buffer-menu-no-header ()
  (beginning-of-line)
  (if (or Buffer-menu-use-header-line
	  (not (tabulated-list-header-overlay-p (point))))
      t
    (ding)
    (forward-line 1)
    nil))

(defun Buffer-menu-beginning ()
  (goto-char (point-min))
  (unless Buffer-menu-use-header-line
    (forward-line)))


;;; Commands for modifying Buffer Menu entries.

(defun Buffer-menu-mark ()
  "Mark the Buffer menu entry at point for later display.
It will be displayed by the \\<Buffer-menu-mode-map>\\[Buffer-menu-select] command."
  (interactive nil Buffer-menu-mode)
  (tabulated-list-set-col 0 (char-to-string Buffer-menu-marker-char) t)
  (forward-line))

(defun Buffer-menu-unmark (&optional backup)
  "Cancel all requested operations on buffer on this line and move down.
Optional prefix arg means move up."
  (interactive "P" Buffer-menu-mode)
  (Buffer-menu--unmark)
  (forward-line (if backup -1 1)))

(defun Buffer-menu-unmark-all-buffers (mark)
  "Cancel a requested operation on all buffers.
MARK is the character to flag the operation on the buffers.
When called interactively prompt for MARK;  RET remove all marks."
  (interactive "cRemove marks (RET means all):" Buffer-menu-mode)
  (save-excursion
    (goto-char (point-min))
    (when (tabulated-list-header-overlay-p)
      (forward-line))
    (while (not (eobp))
      (let ((xmarks (list (aref (tabulated-list-get-entry) 0)
                          (aref (tabulated-list-get-entry) 2))))
        (when (or (char-equal mark ?\r)
                  (member (char-to-string mark) xmarks))
          (Buffer-menu--unmark)))
      (forward-line))))

(defun Buffer-menu-unmark-all ()
  "Cancel all requested operations on buffers."
  (interactive nil Buffer-menu-mode)
  (Buffer-menu-unmark-all-buffers ?\r))

(defun Buffer-menu-backup-unmark ()
  "Move up and cancel all requested operations on buffer on line above."
  (interactive nil Buffer-menu-mode)
  (forward-line -1)
  (Buffer-menu--unmark))

(defun Buffer-menu--unmark ()
  (tabulated-list-set-col 0 " " t)
  (let ((buf (Buffer-menu-buffer)))
    (when buf
      (if (buffer-modified-p buf)
          (tabulated-list-set-col 2 "*" t)
        (tabulated-list-set-col 2 " " t)))))

(defun Buffer-menu-delete (&optional arg)
  "Mark the buffer on this Buffer Menu buffer line for deletion.
A subsequent \\<Buffer-menu-mode-map>`\\[Buffer-menu-execute]' command
will delete it.

If prefix argument ARG is non-nil, it specifies the number of
buffers to delete; a negative ARG means to delete backwards."
  (interactive "p" Buffer-menu-mode)
  (if (or (null arg) (= arg 0))
      (setq arg 1))
  (while (> arg 0)
    (when (Buffer-menu-buffer)
      (tabulated-list-set-col 0 (char-to-string Buffer-menu-del-char) t))
    (forward-line 1)
    (setq arg (1- arg)))
  (while (< arg 0)
    (when (Buffer-menu-buffer)
      (tabulated-list-set-col 0 (char-to-string Buffer-menu-del-char) t))
    (forward-line -1)
    (setq arg (1+ arg))))

(defun Buffer-menu-delete-backwards (&optional arg)
  "Mark the buffer on this Buffer Menu line for deletion, and move up.
A subsequent \\<Buffer-menu-mode-map>`\\[Buffer-menu-execute]'
command will delete the marked buffer.  Prefix ARG means move
that many lines."
  (interactive "p" Buffer-menu-mode)
  (Buffer-menu-delete (- (or arg 1))))

(defun Buffer-menu-save ()
  "Mark the buffer on this Buffer Menu line for saving.
A subsequent \\<Buffer-menu-mode-map>`\\[Buffer-menu-execute]' command
will save it."
  (interactive nil Buffer-menu-mode)
  (when (Buffer-menu-buffer)
    (tabulated-list-set-col 2 "S" t)
    (forward-line 1)))

(defun Buffer-menu-not-modified (&optional arg)
  "Mark the buffer on this line as unmodified (no changes to save).
If ARG is non-nil (interactively, with a prefix argument), mark
it as modified."
  (interactive "P" Buffer-menu-mode)
  (with-current-buffer (Buffer-menu-buffer t)
    (set-buffer-modified-p arg))
  (tabulated-list-set-col 2 (if arg "*" " ") t))

(defun Buffer-menu-execute ()
  "Save and/or delete marked buffers in the Buffer Menu.
Buffers marked with \\<Buffer-menu-mode-map>`\\[Buffer-menu-save]' are saved.
Buffers marked with \\<Buffer-menu-mode-map>`\\[Buffer-menu-delete]' are deleted."
  (interactive nil Buffer-menu-mode)
  (save-excursion
    (Buffer-menu-beginning)
    (while (not (eobp))
      (let ((buffer (tabulated-list-get-id))
	    (entry  (tabulated-list-get-entry)))
	(cond ((null entry)
	       (forward-line 1))
	      ((not (buffer-live-p buffer))
	       (tabulated-list-delete-entry))
	      (t
	       (let ((delete (eq (char-after) ?D)))
		 (when (equal (aref entry 2) "S")
		   (condition-case nil
		       (progn
			 (with-current-buffer buffer
			   (save-buffer))
			 (tabulated-list-set-col 2 " " t))
		     (error (warn "Error saving %s" buffer))))
		 (if (and delete
			  (not (eq buffer (current-buffer)))
                          (kill-buffer buffer))
                     (tabulated-list-delete-entry)
		   (forward-line 1)))))))))

(defun Buffer-menu-select ()
  "Select this line's buffer; also, display buffers marked with `>'.
You can mark buffers with the \\<Buffer-menu-mode-map>`\\[Buffer-menu-mark]' command.

This command deletes and replaces all the previously existing windows
in the selected frame, and will remove any marks."
  (interactive nil Buffer-menu-mode)
  (let* ((this-buffer (Buffer-menu-buffer t))
	 (menu-buffer (current-buffer))
	 (others (delq this-buffer (Buffer-menu-marked-buffers t)))
	 (height (/ (1- (frame-height)) (1+ (length others)))))
    (delete-other-windows)
    (switch-to-buffer this-buffer)
    (unless (eq menu-buffer this-buffer)
      (bury-buffer menu-buffer))
    (dolist (buffer others)
      (split-window nil height)
      (other-window 1)
      (switch-to-buffer buffer))
    ;; Back to the beginning!
    (other-window 1)))

(defun Buffer-menu-marked-buffers (&optional unmark)
  "Return the list of buffers marked with `Buffer-menu-mark'.
If UNMARK is non-nil, unmark them."
  (let (buffers)
    (Buffer-menu-beginning)
    (while (re-search-forward "^>" nil t)
      (let ((buffer (Buffer-menu-buffer)))
	(if (and buffer unmark)
	    (tabulated-list-set-col 0 " " t))
	(if (buffer-live-p buffer)
	    (push buffer buffers))))
    (nreverse buffers)))

(defun Buffer-menu-isearch-buffers ()
  "Search for a string through all marked buffers using Isearch."
  (interactive nil Buffer-menu-mode)
  (multi-isearch-buffers (Buffer-menu-marked-buffers)))

(defun Buffer-menu-isearch-buffers-regexp ()
  "Search for a regexp through all marked buffers using Isearch."
  (interactive nil Buffer-menu-mode)
  (multi-isearch-buffers-regexp (Buffer-menu-marked-buffers)))

(defun Buffer-menu-multi-occur (regexp &optional nlines)
  "Show all lines in marked buffers containing a match for a regexp."
  (interactive (occur-read-primary-args) Buffer-menu-mode)
  (multi-occur (Buffer-menu-marked-buffers) regexp nlines))


(autoload 'etags-verify-tags-table "etags")
(defun Buffer-menu-visit-tags-table ()
  "Visit the tags table in the buffer on this line.  See `visit-tags-table'."
  (interactive nil Buffer-menu-mode)
  (let* ((buf (Buffer-menu-buffer t))
         (file (buffer-file-name buf)))
    (cond
     ((not file) (error "Specified buffer has no file"))
     ((and buf (with-current-buffer buf
                 (etags-verify-tags-table)))
      (visit-tags-table file))
     (t (error "Specified buffer is not a tags-table")))))

(defun Buffer-menu-1-window ()
  "Select this line's buffer, alone, in full frame."
  (interactive nil Buffer-menu-mode)
  (switch-to-buffer (Buffer-menu-buffer t))
  (bury-buffer (other-buffer))
  (delete-other-windows))

(defun Buffer-menu-this-window ()
  "Select this line's buffer in this window."
  (interactive nil Buffer-menu-mode)
  (switch-to-buffer (Buffer-menu-buffer t)))

(defun Buffer-menu-other-window ()
  "Select this line's buffer in other window, leaving buffer menu visible."
  (interactive nil Buffer-menu-mode)
  (switch-to-buffer-other-window (Buffer-menu-buffer t)))

(defun Buffer-menu-switch-other-window ()
  "Make the other window select this line's buffer.
The current window remains selected."
  (interactive nil Buffer-menu-mode)
  (display-buffer (Buffer-menu-buffer t) t))

(defun Buffer-menu-2-window ()
  "Select this line's buffer, with previous buffer in second window."
  (interactive nil Buffer-menu-mode)
  (let ((buff (Buffer-menu-buffer t))
	(menu (current-buffer)))
    (delete-other-windows)
    (switch-to-buffer (other-buffer))
    (switch-to-buffer-other-window buff)
    (bury-buffer menu)))

(defun Buffer-menu-toggle-read-only ()
  "Toggle read-only status of buffer on this line.
This behaves like invoking \\[read-only-mode] in that buffer."
  (interactive nil Buffer-menu-mode)
  (let ((read-only
         (with-current-buffer (Buffer-menu-buffer t)
           (read-only-mode 'toggle)
           buffer-read-only)))
    (tabulated-list-set-col 1 (if read-only "%" " ") t)))

(defun Buffer-menu-bury ()
  "Bury the buffer listed on this line."
  (interactive nil Buffer-menu-mode)
  (let ((buffer (tabulated-list-get-id)))
    (cond ((null buffer))
	  ((buffer-live-p buffer)
	   (bury-buffer buffer)
	   (save-excursion
	     (let ((elt (tabulated-list-delete-entry)))
	       (goto-char (point-max))
	       (apply 'tabulated-list-print-entry elt)))
	   (message "Buffer buried."))
	  (t
	   (tabulated-list-delete-entry)
	   (message "Buffer is dead; removing from list.")))))

(defun Buffer-menu-view ()
  "View this line's buffer in View mode."
  (interactive nil Buffer-menu-mode)
  (view-buffer (Buffer-menu-buffer t)))

(defun Buffer-menu-view-other-window ()
  "View this line's buffer in View mode in another window."
  (interactive nil Buffer-menu-mode)
  (view-buffer-other-window (Buffer-menu-buffer t)))

;;; Functions for populating the Buffer Menu.

;;;###autoload
(defun list-buffers-noselect (&optional files-only buffer-list filter-predicate)
  "Create and return a Buffer Menu buffer.
This is called by `buffer-menu' and others as a subroutine.

If FILES-ONLY is non-nil, show only file-visiting buffers.
If BUFFER-LIST is non-nil, it should be either a list of buffers
or a function that returns a list of buffers; it means
list those buffers and no others.
See more at `Buffer-menu-buffer-list'.
If FILTER-PREDICATE is non-nil, it should be a function
that filters out buffers from the list of buffers.
See more at `Buffer-menu-filter-predicate'."
  (let ((old-buffer (current-buffer))
	(buffer (get-buffer-create "*Buffer List*")))
    (with-current-buffer buffer
      (Buffer-menu-mode)
      (setq Buffer-menu-files-only
	    (and files-only (>= (prefix-numeric-value files-only) 0)))
      (setq Buffer-menu-buffer-list buffer-list)
      (setq Buffer-menu-filter-predicate filter-predicate)
      (list-buffers--refresh buffer-list old-buffer)
      (tabulated-list-print))
    buffer))

(defun Buffer-menu-mouse-select (event)
  "Select the buffer whose line you click on."
  (interactive "e" Buffer-menu-mode)
  (select-window (posn-window (event-end event)))
  (let ((buffer (tabulated-list-get-id (posn-point (event-end event)))))
    (when (buffer-live-p buffer)
      (if (and (window-dedicated-p)
	       (eq (selected-window) (frame-root-window)))
	  (switch-to-buffer-other-frame buffer)
	(switch-to-buffer buffer)))))

(defun list-buffers--refresh (&optional buffer-list old-buffer)
  ;; Set up `tabulated-list-format'.
  (let ((size-width Buffer-menu-size-width)
        (marked-buffers (Buffer-menu-marked-buffers))
        (buffer-menu-buffer (current-buffer))
	(show-non-file (not Buffer-menu-files-only))
	(filter-predicate (and (functionp Buffer-menu-filter-predicate)
			       Buffer-menu-filter-predicate))
	entries name-width)
    ;; Collect info for each buffer we're interested in.
    (dolist (buffer (cond
                     ((functionp buffer-list)
                      (funcall buffer-list))
                     (buffer-list)
                     ((functionp Buffer-menu-buffer-list)
                      (funcall Buffer-menu-buffer-list))
                     (Buffer-menu-buffer-list)
                     (t (buffer-list
                         (if Buffer-menu-use-frame-buffer-list
                             (selected-frame))))))
      (with-current-buffer buffer
	(let* ((name (buffer-name))
	       (file buffer-file-name))
	  (when (and (buffer-live-p buffer)
		     (or buffer-list
			 (and (or (not (string= (substring name 0 1) " "))
                                  file)
			      (not (eq buffer buffer-menu-buffer))
			      (or file show-non-file)
			      (or (not filter-predicate)
				  (funcall filter-predicate buffer)))))
	    (push (list buffer
			(vector (cond
                                 ((eq buffer old-buffer) ".")
                                 ((member buffer marked-buffers) ">")
                                 (t " "))
				(if buffer-read-only "%" " ")
				(if (buffer-modified-p) "*" " ")
				(Buffer-menu--pretty-name name)
				(number-to-string (buffer-size))
				(concat (format-mode-line mode-name
                                                          nil nil buffer)
					(if mode-line-process
					    (format-mode-line mode-line-process
							      nil nil buffer)))
				(Buffer-menu--pretty-file-name file)))
		  entries)))))
    (setq name-width (if (functionp Buffer-menu-name-width)
                         (funcall Buffer-menu-name-width (mapcar #'car entries))
                       Buffer-menu-name-width))
    (setq tabulated-list-format
	  (vector '("C" 1 t :pad-right 0)
		  '("R" 1 t :pad-right 0)
		  '("M" 1 t)
		  `("Buffer" ,name-width t)
		  `("Size" ,size-width tabulated-list-entry-size->
                    :right-align t)
		  `("Mode" ,Buffer-menu-mode-width t)
		  '("File" 1 t)))
    (setq tabulated-list-use-header-line Buffer-menu-use-header-line)
    (setq tabulated-list-entries (nreverse entries)))
  (tabulated-list-init-header))

(defun tabulated-list-entry-size-> (entry1 entry2)
  (> (string-to-number (aref (cadr entry1) 4))
     (string-to-number (aref (cadr entry2) 4))))

(defun Buffer-menu--pretty-name (name)
  (propertize name
	      'font-lock-face 'buffer-menu-buffer
	      'mouse-face 'highlight))

(defun Buffer-menu--pretty-file-name (file)
  (cond (file
	 (abbreviate-file-name file))
	((bound-and-true-p list-buffers-directory)
         (abbreviate-file-name list-buffers-directory))
	(t "")))

;;; buff-menu.el ends here
