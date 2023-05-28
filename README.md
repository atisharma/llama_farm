# llama-farm

Chat with multiple bot personalities fronting a locally-hosted LLaMA model and/or gpt-3.5-turbo, in the comfort of a beautiful 1970's user interface.

It has a long-term chat memory that recalls conversation relevant to the current topic
(backed by a vector store).

Ask it questions about your own documents and information, stuff on arXiv, youtube or wikipedia.
I recommend you are selective about what you ingest as the quality of information available is more important than the quantity.

Llama-farm uses hwchase17/langchain, oobabooga/text-generation-webui (via its OpenedAI API extension) for local models, and various other bricks. It works surprisingly well with Wizard-Vicuna-13B-Uncensored. It even works very well with WizardLM-7B!

Copy the `config.toml.example` to `config.toml`.
To use openAI, you need to set your key in `config.toml`.

Probably you need cuda at least for the embeddings, I'm not sure.
