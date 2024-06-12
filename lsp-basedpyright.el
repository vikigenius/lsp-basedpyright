;;; lsp-basedpyright.el --- LSP integration for basedpyright  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Vikash Balasubramanian

;; Author: Vikash Balasubramanian <master.bvik@gmail.com>
;; Maintainer: Vikash Balasubramanian <master.bvik@gmail.com>
;; URL: https://github.com/vikigenius/lsp-basedpyright
;; Version: 0.1.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: languages

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; lsp-basedpyright fork intended to work with basedbasedpyright
;;

;;; Code:

(require 'lsp-mode)
(require 'dash)
(require 'ht)
(require 'cl-lib)

;; Group declaration
(defgroup lsp-basedpyright nil
  "LSP support for python using the BasedPyright Language Server."
  :group 'lsp-mode
  :link '(url-link "https://github.com/microsoft/basedpyright"))

(defcustom lsp-basedpyright-langserver-command-args '("--stdio")
  "Command to start basedpyright-langserver."
  :type '(repeat string)
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-disable-language-services nil
  "Disables all language services except for \"hover\"."
  :type 'boolean
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-disable-organize-imports nil
  "Disables the \"Organize Imports\" command."
  :type 'boolean
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-use-library-code-for-types t
  "Determines whether to analyze library code.
In order to extract type information in the absence of type stub files.
This can add significant overhead and may result in
poor-quality type information.
The default value for this option is true."
  :type 'boolean
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-diagnostic-mode "openFilesOnly"
  "Determines basedpyright diagnostic mode.
Whether basedpyright analyzes (and reports errors for) all files
in the workspace, as indicated by the config file.
If this option is set to \"openFilesOnly\", basedpyright analyzes only open files."
  :type '(choice
          (const "openFilesOnly")
          (const "workspace"))
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-typechecking-mode "basic"
  "Determines the default type-checking level used by basedpyright.
This can be overridden in the configuration file."
  :type '(choice
          (const "off")
          (const "basic")
          (const "strict"))
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-log-level "info"
  "Determines the default log level used by basedpyright.
This can be overridden in the configuration file."
  :type '(choice
          (const "error")
          (const "warning")
          (const "info")
          (const "trace"))
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-auto-search-paths t
  "Determines whether basedpyright automatically adds common search paths.
i.e: Paths like \"src\" if there are no execution environments defined in the
config file."
  :type 'boolean
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-extra-paths []
  "Paths to add to the default execution environment extra paths.
If there are no execution environments defined in the config file."
  :type 'lsp-string-vector
  :group 'lsp-basedpyright)
(make-variable-buffer-local 'lsp-basedpyright-extra-paths)

(defcustom lsp-basedpyright-auto-import-completions t
  "Determines whether basedpyright offers auto-import completions."
  :type 'boolean
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-stub-path ""
  "Path to directory containing custom type stub files."
  :type 'directory
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-venv-path nil
  "Path to folder with subdirectories that contain virtual environments.
Virtual Envs specified in basedpyrightconfig.json
will be looked up in this path."
  :type '(choice (const :tag "None" nil) file)
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-venv-directory nil
  "Folder with subdirectories that contain virtual environments.
Virtual Envs specified in basedpyrightconfig.json
will be looked up in this path."
  :type '(choice (const :tag "None" nil) directory)
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-typeshed-paths []
  "Paths to look for typeshed modules.
BasedPyright currently honors only the first path in the array."
  :type 'lsp-string-vector
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-multi-root t
  "If non nil, lsp-basedpyright will be started in multi-root mode."
  :type 'boolean
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-python-executable-cmd "python"
  "Command to specify the Python command for basedpyright.
Similar to the `python-shell-interpreter', but used only with mspyls.
Useful when there are multiple python versions in system.
e.g, there are `python2' and `python3', both in system PATH,
and the default `python' links to python2,
set as `python3' to let ms-pyls use python 3 environments."
  :type 'string
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-prefer-remote-env t
  "If non nil, lsp-basedpyright will prefer remote python environment.
Only available in Emacs 27 and above."
  :type 'boolean
  :group 'lsp-basedpyright)

(defcustom lsp-basedpyright-python-search-functions
  '(lsp-basedpyright--locate-python-venv
    lsp-basedpyright--locate-python-python)
  "List of functions to search for python executable."
  :type 'list
  :group 'lsp-basedpyright)

(defun lsp-basedpyright--locate-venv ()
  "Look for virtual environments local to the workspace."
  (or lsp-basedpyright-venv-path
      (and lsp-basedpyright-venv-directory
           (-when-let (venv-base-directory (locate-dominating-file default-directory lsp-basedpyright-venv-directory))
             (concat venv-base-directory lsp-basedpyright-venv-directory)))
      (-when-let (venv-base-directory (locate-dominating-file default-directory "venv/"))
        (concat venv-base-directory "venv"))
      (-when-let (venv-base-directory (locate-dominating-file default-directory ".venv/"))
        (concat venv-base-directory ".venv"))))

(defun lsp-basedpyright--locate-python-venv ()
  "Find a python executable based on the current virtual environment."
  (executable-find (f-expand "bin/python" (lsp-basedpyright--locate-venv))))

(defun lsp-basedpyright--locate-python-python ()
  "Find a python executable based on the version of python on the PATH."
  (with-no-warnings
    (if (>= emacs-major-version 27)
        (executable-find lsp-basedpyright-python-executable-cmd lsp-basedpyright-prefer-remote-env)
      (executable-find lsp-basedpyright-python-executable-cmd))))

(defun lsp-basedpyright-locate-python ()
  "Find a python executable cmd for the workspace."
  (cl-some #'funcall lsp-basedpyright-python-search-functions))

(defun lsp-basedpyright--begin-progress-callback (workspace &rest _)
  "Log begin progress information.
Current LSP WORKSPACE should be passed in."
  (when lsp-progress-via-spinner
    (with-lsp-workspace workspace
                        (--each (lsp--workspace-buffers workspace)
                          (when (buffer-live-p it)
                            (with-current-buffer it
                              (lsp--spinner-start))))))
  (lsp-log "BasedPyright language server is analyzing..."))

(defun lsp-basedpyright--report-progress-callback (_workspace params)
  "Log report progress information.
First element of PARAMS will be passed into `lsp-log'."
  (when (and (arrayp params) (> (length params) 0))
    (lsp-log (aref params 0))))

(defun lsp-basedpyright--end-progress-callback (workspace &rest _)
  "Log end progress information.
Current LSP WORKSPACE should be passed in."
  (when lsp-progress-via-spinner
    (with-lsp-workspace workspace
                        (--each (lsp--workspace-buffers workspace)
                          (when (buffer-live-p it)
                            (with-current-buffer it
                              (lsp--spinner-stop))))))
  (lsp-log "BasedPyright language server is analyzing...done"))

(defun lsp-basedpyright-organize-imports ()
  "Organize imports in current buffer."
  (interactive)
  (lsp-send-execute-command "basedpyright.organizeimports"
                            (vector (concat "file://" (buffer-file-name)))))

(lsp-register-custom-settings
 `(("basedpyright.disableLanguageServices" lsp-basedpyright-disable-language-services t)
   ("basedpyright.disableOrganizeImports" lsp-basedpyright-disable-organize-imports t)
   ("python.analysis.autoImportCompletions" lsp-basedpyright-auto-import-completions t)
   ("python.analysis.typeshedPaths" lsp-basedpyright-typeshed-paths)
   ("python.analysis.stubPath" lsp-basedpyright-stub-path)
   ("python.analysis.useLibraryCodeForTypes" lsp-basedpyright-use-library-code-for-types t)
   ("python.analysis.diagnosticMode" lsp-basedpyright-diagnostic-mode)
   ("python.analysis.typeCheckingMode" lsp-basedpyright-typechecking-mode)
   ("python.analysis.logLevel" lsp-basedpyright-log-level)
   ("python.analysis.autoSearchPaths" lsp-basedpyright-auto-search-paths t)
   ("python.analysis.extraPaths" lsp-basedpyright-extra-paths)
   ("python.pythonPath" lsp-basedpyright-locate-python)
   ;; We need to send empty string, otherwise  basedpyright-langserver fails with parse error
   ("python.venvPath" (lambda () (or lsp-basedpyright-venv-path "")))))

(lsp-dependency 'basedpyright
                '(:system "basedpyright-langserver")
                '(:npm :package "basedpyright"
                  :path "basedpyright-langserver"))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection (lambda ()
                                          (cons (lsp-package-path 'basedpyright)
                                                lsp-basedpyright-langserver-command-args)))
  :major-modes '(python-mode python-ts-mode)
  :server-id 'basedpyright
  :multi-root lsp-basedpyright-multi-root
  :priority 2
  :initialized-fn (lambda (workspace)
                    (with-lsp-workspace workspace
                                        ;; we send empty settings initially, LSP server will ask for the
                                        ;; configuration of each workspace folder later separately
                                        (lsp--set-configuration
                                         (make-hash-table :test 'equal))))
  :download-server-fn (lambda (_client callback error-callback _update?)
                        (lsp-package-ensure 'basedpyright callback error-callback))
  :notification-handlers (lsp-ht ("basedpyright/beginProgress" 'lsp-basedpyright--begin-progress-callback)
                                 ("basedpyright/reportProgress" 'lsp-basedpyright--report-progress-callback)
                                 ("basedpyright/endProgress" 'lsp-basedpyright--end-progress-callback))))

(lsp-register-client
 (make-lsp-client
  :new-connection
  (lsp-tramp-connection (lambda ()
                          (cons (executable-find "basedpyright-langserver" t)
                                lsp-basedpyright-langserver-command-args)))
  :major-modes '(python-mode python-ts-mode)
  :server-id 'basedpyright-remote
  :multi-root lsp-basedpyright-multi-root
  :remote? t
  :priority 1
  :initialized-fn (lambda (workspace)
                    (with-lsp-workspace workspace
                                        ;; we send empty settings initially, LSP server will ask for the
                                        ;; configuration of each workspace folder later separately
                                        (lsp--set-configuration
                                         (make-hash-table :test 'equal))))
  :notification-handlers (lsp-ht ("basedpyright/beginProgress" 'lsp-basedpyright--begin-progress-callback)
                                 ("basedpyright/reportProgress" 'lsp-basedpyright--report-progress-callback)
                                 ("basedpyright/endProgress" 'lsp-basedpyright--end-progress-callback))))


(provide 'lsp-basedpyright)
;;; lsp-basedpyright.el ends here
