"
Chat management functions.
"

(require hyrule.argmove [-> ->>])

(import openai [OpenAI])

(import llama-farm [texts utils])
(import llama-farm.documents [token-count])
(import llama-farm.utils [first last
                          params config
                          append prepend
                          msg assistant system])


(defclass GenerationError [Exception])


(defn user [content]
  (msg "user" content (config "user")))

(defn api-params [bot]
  (let [p (params bot)]
    (.pop p "balacoon_speaker")
    (.pop p "bark_voice")
    (.pop p "system_prompt")
    (.pop p "context_length")
    p))

(defn clean-messages [messages]
  "API doesn't allow extra fields."
  (lfor m messages
        {"role" (:role m)
         "content" (:content m)}))

;;; -----------------------------------------------------------------------------

(defn respond [bot messages #** kwargs]
  "Reply to a list of messages and return just content.
The messages should already have the standard roles."
  (if (> (token-count messages) (:context-length (params bot) 2000))
      (raise (GenerationError f"Messages too long for context: {(token-count messages)}."))
      (let [defaults {"api_key" "n/a"
                      "model" "gpt-3.5-turbo"}
            p (api-params bot)
            params (| defaults p kwargs)
            client (OpenAI :api-key (.pop params "api_key")
                           :base_url (.pop params "api_base"))
            response (client.chat.completions.create
                       :messages (clean-messages messages)
                       #** params)]
        (-> response.choices
            (first)
            (. message)
            (. content)))))

(defn edit [bot text instruction #** kwargs]
  "Follow an instruction.
`input`: The input text to use as a starting point for the edit.
`instruction`: how the model should edit the prompt."
  (respond bot
           [(system instruction)
            (user text)]
           #** kwargs))

(defn chat [bot messages #** kwargs] ; -> message
  "An assistant response (message) to a list of messages.
The messages should already have the standard roles."
  (msg "assistant"
       (respond bot messages #** kwargs)
       bot))

;;; -----------------------------------------------------------------------------
;;; Prompts over messages -> text
;;; -----------------------------------------------------------------------------

(defn msgs->topic [bot messages]
  "Create a topic summary from messages."
  (respond bot [(system "Your sole purpose is to express the topic of conversation in one short sentence.")
                #* messages
                (user "Summarize the topic of conversation before now in as few words as possible.")
                (assistant "The topic is as follows:")]))

(defn msgs->points [bot messages]
  "Create bullet points from messages."
  (respond bot [(system "Your sole purpose is to summarize the conversation into bullet points.")
                #* messages
                (user "Summarize this conversation before now as a markdown list, preserving the most interesting, pertinent and important points.")
                (assistant "The main points are as follows:")]))

(defn msgs->summary [bot messages]
  "Create summary from messages."
  (respond bot [(system "You are a helpful assistant who follows instructions carefully.")
                #* messages
                (user "Please edit down the conversation before now into a single concise paragraph, preserving the most interesting, pertinent and important points.")
                (assistant "The summary is as follows:")]))

(defn text&msgs->reply [bot messages context query]
  "Respond in the context of messages and text.
The text should not be so long as to cause context length problems, so summarise it first if necessary."
  (respond bot [(system "You are a helpful assistant who follows instructions carefully.")
                #* messages
                (user f"{query}

Consider the following additional context before responding:
{context}")]))

(defn complete-json [template instruction context [max-tokens 600]]
  "Fill in a JSON template according to context. Return list, dict or None.
JSON completion is a bit unreliable, depending on the model."
  (let [messages [(system "You will be given a JSON template to complete. You must stick very closely to the format of the template.")
                  (system instruction)
                  (user context)
                  (system "Below is the JSON template to complete.")
                  (user template)
                  (system "Now, complete the template. Give only valid JSON, no other text, context or explanation.")]
        response (respond messages :max-tokens max-tokens)
        match (re.search r"[^{\[]*([\[{].*[}\]])" response :flags re.S)]
    (try
      (when match
        (-> match
            (.groups)
            (first)
            (json.loads)))
      (except [json.decoder.JSONDecodeError]))))

(defn text->topic [bot text]
  "Create a topic summary from text."
  (respond bot [(system "You are a helpful assistant who follows instructions carefully.")
                (user f"Please express the topic of the following text in as few words as possible:

{text}")
                (assistant "The topic is as follows:")]))

(defn text->points [bot text]
  "Create bullet points from text."
  (respond bot [(system "You are a helpful assistant who follows instructions carefully.")
                (user f"Summarize the following text as a list of bullet points, preserving the most interesting, pertinent and important points.

{text}")
                (assistant "The points are as follows:")]))

(defn text->summary [bot text]
  "Create short summary from text."
  (respond bot [(system "You are a helpful assistant who follows instructions carefully.")
                (user f"Please concisely rewrite the following text, preserving the most interesting, pertinent and important points.

{text}")
                (assistant "The summary is as follows:")]))

(defn text->extract [bot query text]
  "Extract points relevant to a query from text."
  (respond bot [(system "You are a helpful assistant who follows instructions carefully.")
                (user f"{query}

Please concisely rewrite the following text, extracting the points most interesting, pertinent and important to the preceding query. Don't invent information. If there is no relevant information, be silent.

{text}")
                (assistant "The points are as follows:")]))
