"
Set up llms.
"

(import langchain.llms [OpenAI])
(import langchain.chat-models [ChatOpenAI])

(import utils [config])


(setv davinci (OpenAI :openai_api_key (config "openai" "secret")
                      :model_name "text-davinci-003"
                      :openai_api_base (config "openai" "base-url")))

(setv gpt-3p5-turbo (ChatOpenAI :openai_api_key (config "openai" "secret")
                                :model_name "gpt-3.5-turbo"
                                :openai_api_base (config "openai" "base-url")))
