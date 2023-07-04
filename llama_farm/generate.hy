"
Chat management functions.
"

(require hyrule.argmove [-> ->>])

(import openai [ChatCompletion Edit])

(import llama-farm [texts utils])
(import .utils [first last
                params config
                append prepend
                msg assistant system])


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

(defn edit [bot text instruction #** kwargs]
  "Follow an instruction.
`input`: The input text to use as a starting point for the edit.
`instruction`: how the model should edit the prompt."
  (let [max_tokens (config "max_tokens")
        p (api-params bot)
        key (.pop p "api_key" "n/a")
        chat-model (.pop p "chat_model" "gpt-3.5-turbo")
        completion-model (.pop p "completion_model"  "text-davinci-edit-001")
        response (Edit.create
                   :input text
                   :instruction instruction
                   :model completion-model
                   :api_key key
                   #** (| p kwargs))]
    (-> response.choices
        (first)
        (:text))))

(defn respond [bot messages #** kwargs]
  "Reply to a list of messages and return just content.
The messages should already have the standard roles."
  (let [max_tokens (config "max_tokens")
        p (api-params bot)
        key (.pop p "api_key" "n/a")
        chat-model (.pop p "chat_model" "gpt-3.5-turbo")
        completion-model (.pop p "completion_model"  "text-davinci-edit-001")
        response (ChatCompletion.create
                   :messages (clean-messages messages)
                   :model chat-model
                   :api_key key
                   #** (| {"max_tokens" max_tokens} p kwargs))]
    (-> response.choices
        (first)
        (:message)
        (:content))))

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

;;; -----------------------------------------------------------------------------
;;; Prompts over paragraphs of text -> text
;;; -----------------------------------------------------------------------------

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