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
It can summarize Youtube video transcripts, URLs and your files.

### Compatibility and technology
Llama-farm speaks to any OpenAI-compatible API:

- oobabooga/text-generation-webui (via its OpenAI-compatible API extension)
- OpenAI
- lm-sys/FastChat (untested)
- keldenl/gpt-llama.cpp (untested)

Llama-farm uses microsoft/guidance and hwchase17/langchain for some abstractions (see limitations).

The storage is backed by [faiss](https://github.com/facebookresearch/faiss). The wrapper to [chromadb](https://github.com/chroma-core/chroma) is
written but is not currently used or tested.

### Help text
The help text is [here](llama_farm/help.md).

### Setup
Copy the `config.toml.example` to `config.toml`.
To use openAI, you need to set your key in `config.toml`.

There are a lot of dependencies so it's recommended you install everything in a virtual environment.
Either clone the repo, install the `requirements.txt` and run the module
```
$ <activate your venv>
$ git clone https://github.com/atisharma/llama_farm
$ cd llama_farm
$ pip install -r requirements.txt
$ python -m llama_farm
```

Or, install using pip
```
$ <activate your venv>
$ pip install git+https://github.com/atisharma/llama_farm
$ llama-farm
```

### Suitable models
Llama-farm works very well with OpenAI's gpt-3.5-turbo.
Wizard-Vicuna-Uncensored, WizardLM, etc also work very well. It even
works surprisingly well with WizardLM-7B!  But see limitations below.

### Limitations and bugs
- Larger LLaMA models (30B) work much better.
- The context length limitation of Llama models (2048 tokens) is half or
less that of OpenAI's models.
- The OpenAI API (and compatible ones) do not expose a number of
  capabilities that local models have. The full power of the guidance
  library is therefore not available.

### Roadmap
- Replace LLMs with guides:
  * ask.xyz
  * models.reply (do first, easy)
- Reconsider store document size, since summarization works well
- Define tools for freeform memory access rather than /command syntax
- You can grep the codebase for "TODO:" tags
- Define JSON API templates for other web tools
- Self-chat between bots with intention/task injection
