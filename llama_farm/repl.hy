"
The main REPL where we chat to the bot and issue commands.
"

(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import itertools [chain repeat])

(import .utils [config rlinput user])
(import .parser [parse set-bot])

(import .interface [banner
                    clear
                    console
                    format-msg
                    get-margin
                    info])


(defn run []
  "Launch the REPL, which takes user input, parses
it, and passes it to the appropriate action."
  (banner)
  (info "Type **/help** for help\n")
  (console.rule)
  (set-bot)
  (let [chat-history []]
    (try
      (while True
        (let [username (config "repl" "user")
              margin (get-margin chat-history)
              user-prompt (format-msg (user "" username) margin)
              line (.strip (rlinput user-prompt))]
          (cond (or (.startswith line "/q") (.startswith line "/exit")) (break)
                :else (when line
                        (let [user-msg (user line username)]
                          (setv chat-history
                                (parse user-msg chat-history)))))))
                            
      (except [EOFError]
        (print)))))
