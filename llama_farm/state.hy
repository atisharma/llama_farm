"
Shared state maintained in the vector stores.
"

(import os)

(import .utils [config])
(import llama-farm [store])


;; TODO: test with Chroma, present an option in the config
(setv knowledge-store (store.faiss (os.path.join (config "storage" "path")
                                                 "knowledge.faiss")))

(setv chat-store (store.faiss (os.path.join (config "storage" "path")
                                            "chat.faiss")))
