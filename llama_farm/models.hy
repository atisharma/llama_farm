"
Set up and operate the chat models from the definitions in `config.yaml`.

Can talk to OpenAI or compatible, such as Oobabooga/text-generation-webui's
openai extension or lm-sys/FastChat.
"

;; TODO: use OpenAI's `name` parameter.
;; TODO: use my own API abstraction as langchain's is more complicated that just using the API directly.

(require hyrule.argmove [-> ->>])

(import functools [partial])
(import itertools [cycle])

(import langchain.chat-models [ChatOpenAI])
(import langchain.chat-models.openai [_convert-message-to-dict :as msg->dict
                                      _convert-dict-to-message :as dict->msg])

(import .utils [config system])
(import .fake [ChatFakeList])


(defn bots []
  "Just a list of bots defined in the config."
  (-> (config "bots")
      (.keys)
      (list)))

(defn params [bot]
  "Return a dict with parameters dict as values and bot name as keys."
  (get (config "bots") (.lower bot)))

(defn model [bot]
  "Return correct chat model instance for the kind.
   This allow construction based on the model name only."
  (let [pms (params bot)]
    (.pop pms "system_prompt" None) ; don't want system prompt here
    (match (.pop pms "kind" "unknown")
           "openai" (ChatOpenAI #** pms)
           "openedai" (ChatOpenAI :openai_api_key "n/a"
                                  :openai_api_base (.pop pms "url")
                                  :model_name (or (.pop pms "model_name" None) "local")
                                  #** pms)
           "fake" (ChatFakeList)
           _ (ChatFakeList))))

(defn reply [bot chat-history]
  "Return the reply message from the chat model."
  ; we go via langchain's ridiculous Message object.
  ; Construct API instance on the fly because it sets variables at the class level.
  (->> chat-history
       (map dict->msg)
       (list)
       ((model bot))
       (msg->dict)
       (| {"bot" bot})))
