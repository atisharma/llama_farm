"
Set up chat models.
"

(require hyrule.argmove [-> ->>])
(import functools [partial])

(import langchain.llms [LlamaCpp FakeListLLM])  ; TODO: convert to chat models
(import langchain.chat-models [ChatOpenAI])
(import langchain.chat-models.openai [_convert-message-to-dict :as msg->dict
                                      _convert-dict-to-message :as dict->msg])

(import .utils [config system])


(defn personalities []
  "Just a list of personalities defined in the config."
  (-> (config "personalities")
      (.keys)
      (list)))

(defn params [personality]
  "Return a dict with parameters dict as values and personality name as keys."
  (get (config "personalities") (.lower personality)))

(defn make-model [#** kwargs]
  "Return correct chat model instance for the kind.
   This allow construction based on the model name only."
  (.pop kwargs "system_prompt" None) ; don't need system prompt here
  (match (.pop kwargs "kind" "unknown")
         "openai" (ChatOpenAI #** kwargs)
         "openedai" (ChatOpenAI :openai_api_key "n/a"
                                :openai_api_base (.pop kwargs "url")
                                :model_name (or (.pop kwargs "model_name" None) "local")
                                #** kwargs)
         "llama-cpp" (LlamaCpp #** kwargs)
         "fake" (FakeListLLM #** kwargs)
         "unknown" (FakeListLLM :responses (* ["I'm not talking to you until you specify a kind of language model in the config."] 100))
         _ (FakeListLLM :responses (* ["You need to specify a valid language model 'kind = ...' in the config."] 100))))

(defn _replace-role [personality chat-history]
  "Replace role a with b in all messages for openedai.
   OpenAI expects 'assistant' role, but OpenedAI bots expect 'bot'."
  (match (:kind (params personality) None)
         "openedai" (lfor m chat-history {#** m "role" (.replace (:role m) "assistant" "bot")})
         _ chat-history))

(defn reply [personality chat-history system-prompt]
  "Return the reply message from the chat model."
  ; we go via langchain's ridiculous Message object.
  ; Construct API instance on the fly because it sets variables at the class level.
  (let [model (make-model #** (params personality))]
    (->> chat-history
         (_replace-role personality)
         (+ [(system system-prompt)])
         (map dict->msg)
         (list)
         (model)
         (msg->dict)
         (| {"personality" personality}))))

