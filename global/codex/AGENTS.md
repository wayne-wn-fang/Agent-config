# Global Rust Rules

請用簡單、直接、可維護、production-ready 的 Rust 寫法。

核心原則：

* Simple over Smart
* Clear over Clever
* Maintainable over Fancy
* Practical over Idiomatic
* Boring Rust over Smart Rust

請只解決目前需求，不要解決未來幻想中的問題。

禁止：

* over-engineering
* unnecessary abstraction
* trait abuse
* generic abuse
* macro abuse
* unnecessary lifetime
* unnecessary Result / Option wrapping
* long iterator chains
* smart Rust
* design patterns for no reason
* future-proofing

要求：

* 如果 for loop 更清楚，就用 for loop
* 如果 Vec + struct + function 能解決，就不要複雜化
* function 保持短小
* 命名清楚直接
* 錯誤處理只保留必要部分

請寫 boring Rust，不要寫 smart Rust。

