"
The main REPL where we chat to the bot and issue commands.
"

;; TODO: whisper
;; TODO: eval Hy in user's text, maybe

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import .logger [logging])

(import os)
(import itertools [chain repeat])
(import datetime [datetime])
(import signal [signal SIGINT])
(import readline)

(import llama-farm.utils [config rlinput user file-append barf])
(import llama-farm.parser [parse set-bot bot])
(import llama-farm.chat [commit-chat])
(import llama-farm.interface [banner
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
        (except [e [Exception]]
          (with [f (open "traceback.log" :mode "w" :encoding "UTF-8")]
            (import traceback)
            (traceback.print-exception e :file f))
          (exception))))
    (readline.write-history-file history-file)
    (clear)))
    
