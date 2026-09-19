# -*- mode: snippet -*-
# name: doctest suite
# key: __test.cpp
# --
#include <doctest/doctest.h>

#include <${1:`(let ((base (string-remove-prefix "tst_"
              (string-remove-prefix "test_"
                (file-name-base (or buffer-file-name "test_thing")))))
            (name (doom-project-name)))
        (format "%s/%s.hpp" (if (member name (list nil "-")) "project" name) base))`}>

TEST_CASE("${2:what it should do}") {
  $0
}
