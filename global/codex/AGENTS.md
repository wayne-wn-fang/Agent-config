---
applyTo: "**"
---
# Global Rust Rules

請用簡單、直接、可維護、production-ready 的 Rust 寫法。

核心原則：

* Simple over Smart
* Clear over Clever
* Maintainable over Fancy
* Practical over Idiomatic
* Boring Rust over Smart Rust

請只解決目前需求，不要解決未來幻想中的問題。

當遇到既有 Rust code 時：

請先理解現有程式碼的設計與風格，再進行修改。

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

修改既有 Rust code 時要求：

1. 優先延續原本的 code style，不要為了「更漂亮」而大改架構
2. 不要隨意重構整個模組，只修改目前需求相關的部分
3. 不要因為能重寫就重寫，優先最小修改（minimal diff）
4. 不要破壞原本已經穩定運作的邏輯
5. 如果現有設計合理，就保持一致，不強行套用新的 abstraction
6. 修改時優先 patch，而不是 rewrite
7. 不要把原本容易懂的 code 改成更抽象的版本
8. 不要為了「更 Rust」而讓原本可讀的 code 變難懂
9. 保持原本的 naming convention、error handling style、module structure
10. 如果需要重構，先說明原因，再進行最小範圍重構
11. 如果條件分支很多（大量 if / else if），可以評估是否使用 match 讓邏輯更清楚
12. 如果 match 能明顯提升可讀性與維護性，優先使用 match
13. 不要為了使用 match 而強行改寫，只有在 branch 明確且結構適合時才使用
14. 優先讓邏輯一眼能看懂，而不是追求語法上的 Rust idiomatic

原則：

* Respect existing code
* Minimal diff over perfect rewrite
* Consistency over personal preference
* Stability over elegance
* Readability over cleverness

請像資深工程師在維護 production code 一樣處理，
不是像在重寫 side project。

目標：

修正問題，
不是證明自己比較會寫 code。

請優先：
「安全修改」
而不是：
「全面重構」

請寫 boring Rust，不要寫 smart Rust。
