"
The main REPL where we chat to the bot and issue commands.
"

;; TODO: bark, whisper
;; TODO: eval Hy in user's text

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import logging)
(import os)
(import itertools [chain repeat])
(import datetime [datetime])
(import signal [signal SIGINT])
(import readline)

(import .utils [config rlinput user file-append])
(import .parser [parse set-bot bot])
(import .chat [commit-chat])
(import .interface [banner
                    clear
                    console
                    format-msg
                    get-margin
                    info
                    error
                    exception])


(defn run []
  "Launch the REPL, which takes user input, parses
it, and passes it to the appropriate action."
  (logging.basicConfig :filename (config "logfile")
                       :level logging.WARNING
                       :encoding "utf-8")
  (logging.info f"Starting repl at {(.isoformat (datetime.today))}")
  (banner)
  (info "Enter **/help** for help\n")
  (console.rule)
  (set-bot)
  (let [chat-history []
        history-file (os.path.join (os.path.expanduser "~") ".llama_history")]
    (try
      (readline.read-history-file history-file)
      (except [e [FileNotFoundError]]))
    (while True
      (try
        (let [username (config "user")
              margin (get-margin chat-history)
              user-prompt (format-msg (user "" username) margin)
              line (.strip (rlinput user-prompt))]
          (cond (.startswith line "/quit!") (do
                                              (setv chat-history [])
                                              (break))
                (or (.startswith line "/q")
                    (.startswith line "/exit")) (do (commit-chat bot chat-history)
                                                    (break))
                line (let [user-msg (user line username)]
                       (setv chat-history (parse user-msg chat-history)))))
        (except [KeyboardInterrupt]
          (print)
          (error "**/quit** to exit"))
        (except [Exception]
          (exception))))
    (readline.write-history-file history-file)
    (clear)))
    
