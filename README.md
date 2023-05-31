# llama-farm
Chat with multiple bots with different personalities, hosted locally
or with OpenAI, in the comfort of a beautiful 1970's terminal-themed
REPL.

![A llama with a cuttlefish logo standing in front of the letters LF](logo.png)

### Topical chat memory
Llama-farm has a **long-term chat memory** that recalls previous
conversations. A summary of previous conversation relevant to the
topic (automatically determined) is available to the active bot.

### Knowledge database
Ask it questions about your own documents and information, stored in a
local vector knowledge store. I recommend you are selective about
what you ingest in order to improve the relevance of results. The
quality of information available is more important than the quantity.

### Internet access & summarization
You can ask it questions with access to arXiv or wikipedia.
It can summarize Youtube video transcripts and URLs.

### Compatibility and technology
Llama-farm speaks to any OpenAI-compatible API:

- oobabooga/text-generation-webui (via its OpenAI-compatible API extension)
- OpenAI
- lm-sys/FastChat (untested)

Llama-farm uses hwchase17/langchain for some abstractions (see limitations).

The storage is backed by [faiss](https://github.com/facebookresearch/faiss). The wrapper to [chromadb](https://github.com/chroma-core/chroma) is
written but not currently used.

#### Help text
The help text is [here](llama_farm/help.md).

### Setup
Copy the `config.toml.example` to `config.toml`.
To use openAI, you need to set your key in `config.toml`.
Install the `requirements.txt`.

### Suitable models
Llama-farm works very well with OpenAI's gpt-3.5-turbo.
Wizard-Vicuna-Uncensored also works very well. It even works
surprisingly well with WizardLM-7B!
But see limitations below.

### Limitations and bugs

The context length limitation of Llama models (2048 tokens) is half or
less that of OpenAI's models. Langchain assumes the longer context, so
some commands involving these chains (wikipedia, arxiv, summarization)
may break on locally hosted models.

### Roadmap
- Reduce dependence on langchain's chains; more local prompts
- Self-chat between bots with intention/task injection
