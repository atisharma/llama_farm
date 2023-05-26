(require hyrule.argmove [-> ->> as->])
(require hyrule.control [unless])

(import os)

(import llama-farm [ask store])
(import llama-farm.models [personalities params reply])
(import .utils [config is-url msg system])
(import .interface [print-chat-history format-sources info])

(import requests.exceptions [ConnectionError])


(setv personality (get (personalities) 0))

(setv knowledge-store (store.faiss (os.path.join (config "storage" "path")
                                                 "knowledge.faiss")))

(setv chat-store (store.faiss (os.path.join (config "storage" "path")
                                            "chat.faiss")))

(setv help-str "
To chat, just enter some text.

Lines beginning with **/** are parsed as commands.
The usual readline shortcuts should be available.

#### Commands:

- **/help /h**                   Show this helpful text
- **/quit /q /exit**             Quit
- **/version**                   Show the version of this client
- **/clear**                     Clear the display

#### Personalities:

- **/personalities**             List the available personalities
- **/personality 'name'**        Talk to a particular personality (alice, bob, etc.) and set as current
- **/personality**               Show the current personality to whom unaddressed input goes

#### Conversation:

- **/undo**                      Delete the last pair of items in the conversation
- **/retry**                     Get a new response to the last input
- **/history**                   Print the whole chat history for this session
- **/ask 'query'**               Ask a question with reference to the knowledge store
- **/sources 'query'**           Ask a question with reference to the knowledge store, showing sources
- **/wikipedia 'query'**         Ask a question with reference to wikipedia
- **/arxiv 'arxiv-id' 'query'**  Ask a question about a specific arXiv article

#### Memory:

- **/remember**                  Save the conversation to an personality's long-term memory
- **/ingest 'filename'**         Ingest a filename or directory (recursively) to the knowledge store
- **/ingest 'urls(s)'**          Ingest a single url or list of urls (separated by spaces, no quotes)
")


(defn ingest [df files-or-url]
  "A convenience wrapper."
  (try
    (for [f (.split files-or-url)]
      (if (is-url args)
        (ingest-urls knowledge-store f)
        (ingest-files knowledge-store f)))
    "Done."
    (except [e [ConnectionError]]
      f"*I can't find that URL.*

`{(repr e)}`")
    (except [e [FileNotFoundError]]
      f"*I can't find that file or directory.*

`{(repr e)}`")))

(defn list-personalities []
  "Tabulate the available personalities."
  (let [personality-list (.join ", " (personalities))
        personality-table (.join "\n" (lfor p (personalities)
                                            (let [kind (:kind (params p) "fake")]
                                              f"\t{p :<12}{kind}")))]
    f"*{personality-list} are available.\nThey are of the following types:*\n\n{personality-table}"))
  

(defn parse [human-message chat-history]
  "Take as input human-message: {role: user, content: line}, the chat history: [list messages], and personality: (system prompt string).
   Do the action resulting from `line`, and return reply as a message, or None if appropriate."
  (global personality)
  (let [chain-type (or (config "repl" "chain-type") "stuff")
        system-prompt (:system_prompt (params personality))
        line (:content human-message)]
    (setv [command _ args] (.partition line " "))
    (if (.startswith line "/")
        (match (.lower command)
               "/help" (info help-str)
               "/h" (info help-str)
               "/version" (info (version "llama_farm"))
               ;;
               "/personalities" (info (list-personalities))
               "/personality" (info (cond (in (.lower args) (personalities)) (do (setv personality (.lower args))
                                                                                 f"*You are now talking to {(.title personality)}.*")
                                          (not args) f"*You are talking to {(.title personality)}.*"
                                          :else f"*{args} is not available. You are still talking to {(.title personality)}.*"))
               ;;
               "/ingest" (info (ingest args))
               ;;
               "/wikipedia" (msg "assistant" f"{(:answer (ask.wikipedia model args) "*No answer*")}")
               "/ask" (msg "assistant" f"{(:result (ask.db knowledge-store model args))}")
               "/sources" (msg "assistant" f"{(format-sources (ask.db knowledge-store model args :sources True))}")
               ;;
               "/history" (print-chat-history chat-history)
               _ (info f"*Unknown command **{command}**."))
        (reply personality chat-history system-prompt))))
