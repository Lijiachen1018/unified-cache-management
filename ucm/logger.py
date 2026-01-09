#
# MIT License
#
# Copyright (c) 2025 Huawei Technologies Co., Ltd. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

import os
import inspect
import yaml
import atexit

from ucm.shared.infra import spdlog_logger as logger
# from ucm.shared.infra import source_location


class Logger:

    def __init__(self, name: str = "UC", config_file: str = None):
        self.name = name
        log_config = {}
        if config_file:
            config = self.load_config(config_file)
            if config:
                log_config = config.get("log_config", {})
        print("="*20)
        print(log_config)
        
        path = log_config.get("path", "log/ucm.log")
        max_files = log_config.get("max_files", 3)
        max_size = log_config.get("max_size", 5)
        print(path, max_files, max_size)
        logger.setup(path, max_files, max_size)

    def load_config(self, path: str):
        with open(path, "r", encoding="utf-8") as f:
            config = yaml.safe_load(f) or {}
        return config

    def get_source_location(self):
        """Helper function to print the current file, function, and line number."""
        frame = inspect.currentframe()
        caller_frame = frame.f_back.f_back
        filename = os.path.basename(caller_frame.f_code.co_filename)
        lineno = caller_frame.f_lineno
        func_name = caller_frame.f_code.co_name
        return filename, func_name, lineno
    
    def debug(self, message: str, *args):
        file, func, line = self.get_source_location()
        msg = logger.format(message, args)
        logger.debug(file, func, line, msg)

    def info(self, message: str, *args):
        file, func, line = self.get_source_location()
        msg = logger.format(message, args)
        logger.info(file, func, line, msg)

    def warning(self, message: str, *args):
        file, func, line = self.get_source_location()
        msg = logger.format(message, args)
        logger.warning(file, func, line, msg)

    def error(self, message: str, *args):
        file, func, line = self.get_source_location()
        msg = logger.format(message, args)
        logger.error(file, func, line, msg)
    
    def flush(self):
        logger.flush()

def init_logger(name: str = "UC", config_file: str = None)->Logger:
    return Logger(name, config_file)

def _flush_logger_on_exit():
    """Flush the logger when the program exits."""
    try:
        print("Flushing logger on exit")
        logger.flush()
    except Exception:
        pass  # Ignore errors during exit

# Register flush function to be called at program exit
atexit.register(_flush_logger_on_exit)

def test_logger():
    logger = init_logger()
    logger.debug("debug message")
    logger.info("info message")
    logger.warning("warning message")
    logger.error("error message")
    logger.info("info message with format: {} {}", "test", "test2")
 

if __name__ == "__main__":
    os.environ["UNIFIED_CACHE_LOG_LEVEL"] = "DEBUG"
    test_logger()
