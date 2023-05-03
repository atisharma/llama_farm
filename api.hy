(require hyrule.argmove [-> ->>])

(import requests)
(import requests.exceptions [HTTPError JSONDecodeError ConnectionError])


; just a local default
(setv base-url "http://jupiter.letterbox.pw:5001/v1")


(defn request [url method [json None]]
  " Dispatcher for request. Return a response object. "
  (try
    (match method
           "get" (requests.get url)
           "post" (requests.post url :json json)
           "put" (requests.put url :json json)
           "delete" (requests.delete url))
    (except [ConnectionError]
      (setv r (requests.Response)
            r.status-code "ConnectionError"
            r.reason f"Failed to establish a new connection to {url}")
      r)))
            
(defn format-response [response]
  (let [error {"status-code" response.status-code
                     "reason" response.reason}]
    (try (| error (response.json))
         (except [JSONDecodeError] error))))

(defn get-endpoint [base-url endpoint]
  (-> base-url
      (+ endpoint)
      (request "get")
      (format-response)))

(defn post-endpoint [base-url endpoint payload]
  (-> base-url
      (+ endpoint)
      (request "post" :json payload)
      (format-response)))

(defn put-endpoint [base-url endpoint payload]
  (-> base-url
      (+ endpoint)
      (request "put" :json payload)
      (format-response)))

(defn delete-endpoint [base-url endpoint]
  (-> base-url
      (+ endpoint)
      (request "delete")
      (format-response)))


;;; TODO: sort out base-url more nicely, perhaps using partial?

(defn models [base-url]
  (get-endpoint base-url "/models"))

(defn completion [base-url prompt #** kwargs]
  (post-endpoint base-url "/completions" {"prompt" prompt #** kwargs}))

(defn chat-completion [base-url messages #** kwargs]
  (post-endpoint base-url "/chat/completions" {"messages" messages #** kwargs}))

(defn embedding [base-url _input #** kwargs]
  (post-endpoint base-url "/embeddings" {"input" _input #** kwargs}))

(defn edits [base-url instruction _input #** kwargs]
  (post-endpoint base-url "/edits" {"input" _input
                                    "instruction" instruction
                                    #** kwargs}))
