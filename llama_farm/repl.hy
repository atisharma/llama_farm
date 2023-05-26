
(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import itertools [chain repeat])

(import .utils [config rlinput user])
(import .parser [parse])

(import .interface [banner format-msg get-margin info print-message clear toggle-markdown console])


(defn run []
  "Launch the REPL, which takes user input, parses
it, and passes it to the appropriate action."
  (banner)
  (info "Type **/help** for help\n")
  (console.rule)
  (let [chat-history []]
    (try
      (while True
        (let [username (config "repl" "user")
              margin (get-margin chat-history)
              user-prompt (format-msg (user "" username) margin)
              line (.strip (rlinput user-prompt))]
          (cond (or (.startswith line "/q") (.startswith line "/exit")) (break)
                (.startswith line "/clear") (clear)
                (.startswith line "/width") (set-width line)
                (.startswith line "/markdown") (toggle-markdown)
                :else (when line
                        (let [user-msg (user line username)]
                          (unless (.startswith line "/")
                            (.append chat-history user-msg))
                          (let [reply (parse user-msg chat-history)]
                            (when reply
                              (print-message reply margin)
                              (.append chat-history reply))))))))
                            
      (except [EOFError]
        (print)))))
