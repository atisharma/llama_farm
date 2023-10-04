(import logging)

(import llama-farm.utils [config])


(logging.basicConfig :filename (config "logfile")
                     :level logging.WARNING
                     :encoding "utf-8")
