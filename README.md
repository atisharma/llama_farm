# llama-farm
Chat with multiple bots with different personalities, hosted locally or with OpenAI, in the comfort of a beautiful 1970's user interface.

### Topical memory
Llama-farm has a long-term chat memory that recalls previous conversations. A summary of previous conversation relevant to the topic (automatically determined) is available to the bot.

### Knowledge database
Ask it questions about your own documents and information, stuff on arXiv, youtube or wikipedia.
I recommend you are selective about what you ingest as the quality of information available is more important than the quantity.

### Internet access

### Compatibility and technology
Llama-farm speaks to any OpenAI-compatible API:
- oobabooga/text-generation-webui (via its OpenedAI API extension)
- lm-sys/FastChat
- OpenAI

Llama-farm uses hwchase17/langchain for some abstractions.

The storage is backed by faiss or chromadb.

### Setup
Copy the `config.toml.example` to `config.toml`.
To use openAI, you need to set your key in `config.toml`.
Install the `requirements.txt`.

### Suitable models
Llama-farm works very well with OpenAI's gpt-3.5-turbo of course.
Wizard-Vicuna-Uncensored also works very well. It even works surprisingly well with WizardLM-7B!

#### Help text

The help text is [here](llama_farm/help.md).
