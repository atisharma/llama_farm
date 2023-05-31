"
*** THIS FILE IS AN ONGOING EXPERIMENT AND IS NOT CURRENTLY USED ***

Produce summary text from a longer text.

This is an experiment to get round langchain's assumption of OpenAI's long context length.
This assumption breaks Llama models resulting in broken summaries.
"

(require hyrule.argmove [-> ->> as->])

(import functools [partial])

(import transformers [AutoTokenizer AutoModelForSeq2SeqLM BartForConditionalGeneration])
(import transformers [pipeline])
(import transformers.pipelines.pt-utils [KeyDataset])
(import datasets)

(import langchain.text-splitter [RecursiveCharacterTextSplitter])

(import .utils [config])

#_(setv checkpoint  "sshleifer/distilbart-xsum-12-3"
        model-max-length 1024
        prefix "")

(setv checkpoint "t5-small"
     prefix "summarize: "
     model-max-length 512)

(setv tokenizer (AutoTokenizer.from_pretrained checkpoint)
      model (AutoModelForSeq2SeqLM.from_pretrained checkpoint)) 

(defn fragment [text [chunk-size model-max-length]]
  "List of paragraphs of max length."
  (let [doc-splitter (RecursiveCharacterTextSplitter.from-huggingface-tokenizer
                       :tokenizer tokenizer
                       :chunk-size chunk-size)]
    (->> [text]
         (doc-splitter.create-documents)
         (map (fn [d] (+ prefix (. d page-content))))
         (list))))
  
(defn _summarize-fragment [text]
  (-> text
      (tokenizer :return-tensors "pt"
                 :max-length model-max-length)
                 ;:truncation True)
    (:input-ids)
    (model.generate :num-beams 2
                    :min-length (// model-max-length 4)
                    :max-length (// model-max-length 2))
    (tokenizer.batch-decode :skip-special-tokens True)
    (get 0)))

(defn summarize [text]
  "Summarize a text by splitting into fragments and summarizing each."
  (let [pipe (pipeline :task "summarization"
                       :device-map "auto"
                       ;:device 0
                       :tokenizer tokenizer
                       :model model)
        fragments (fragment text)]
    (->> fragments
         (pipe :batch-size 16
               :truncation None)
         (map (fn [d] (:summary-text d)))
         (.join "\n"))))
        
(defn summarize-recursive [text [max-token-length 1000]]
  "Recursively summarize down to below specified token length.
   This doesn't work very well as it destroys context."
  (let [tokens (:input-ids (tokenizer text))
        token-length (len tokens)]
    (if (> token-length max-token-length)
        (do
          (print f"Summarization pass, {token-length} tokens -> {max-token-length}...")
          (-> text
              (summarize)
              (summarize-recursive :max-token-length max-token-length)))
        text)))

(defn summarize-recursive-llm [bot text [max-token-length 1000]]
  "Recursively summarize down to below specified token length.
   This doesn't work very well as it destroys context."
  (let [tokens (:input-ids (tokenizer text))
        token-length (len tokens)
        _summarize (partial ask.summarize (model bot))]
    (if (> token-length max-token-length)
        (do
          (print f"Summarization pass, {token-length} tokens -> {max-token-length}...")
          (-> text
              (_summarize)
              (summarize-recursive-llm :max-token-length max-token-length)))
        text)))
