"
Set up and operate the chat models from the definitions in `config.yaml`.

Can talk to OpenAI or Oobabooga/text-generation-webui's openai-compatible API.
"

(require hyrule.argmove [-> ->>])
(import functools [partial])

(import langchain.llms [LlamaCpp FakeListLLM])  ; TODO: convert these to chat models
(import langchain.chat-models [ChatOpenAI])
(import langchain.chat-models.openai [_convert-message-to-dict :as msg->dict
                                      _convert-dict-to-message :as dict->msg])

(import .utils [config system])


(defn bots []
  "Just a list of bots defined in the config."
  (-> (config "bots")
      (.keys)
      (list)))

(defn params [bot]
  "Return a dict with parameters dict as values and bot name as keys."
  (get (config "bots") (.lower bot)))

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

(defn model [bot]
  "Return the current active model."
  (make-model #** (params bot)))

(defn _replace-role [bot chat-history]
  "Replace role a with b in all messages for openedai.
   OpenAI expects 'assistant' role, but OpenedAI bots expect 'bot'."
  (match (:kind (params bot) None)
         "openedai" (lfor m chat-history {#** m "role" (.replace (:role m) "assistant" "bot")})
         "openai" (lfor m chat-history {#** m "role" (.replace (:role m) "bot" "assistant")})
         _ chat-history))

(defn reply [bot chat-history]
  "Return the reply message from the chat model."
  ; we go via langchain's ridiculous Message object.
  ; Construct API instance on the fly because it sets variables at the class level.
  (->> chat-history
       (_replace-role bot)
       (map dict->msg)
       (list)
       ((model bot))
       (msg->dict)
       (| {"bot" bot})))
