/*
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// This String extension provides utility functions to convert strings to their
/// HTML named character entity equivalents and vice versa. Named character
/// entities are often used to mitigate XSS attacks that, for example, inject
/// scripts into web pages.
public extension String {
    /// Return string as HTML escaped by replacing certain characters with their
    /// HTML named character entity equivalents.
    /// For example, this function turns
    /// `"<script>alert(\"abc\")</script>"`
    /// into
    /// `"&lt;script&gt;alert(&quot;abc&quot;)&lt;/script&gt;"`
    /// - parameter decimal: Specifies if decimal escapes should be used.
    /// *Optional*. Defaults to `false`.
    /// - parameter useNamedReferences: Specifies if named character references
    /// should be used whenever possible. *Optional*. Defaults to `true`.
    public func htmlEscape(
        decimal: Bool = false,
        useNamedReferences: Bool = true) -> String {
        let unicodes = self.unicodeScalars

        // result buffer
        var str: String = ""

        // indices for substringing and iterating
        var leftIndex = unicodes.startIndex
        var currentIndex = leftIndex

        while (currentIndex < unicodes.endIndex) {
            let nextIndex = unicodes.index(after: currentIndex)
            let unicode = unicodes[currentIndex].value

            if useNamedReferences,
                let entity = html4NamedCharactersEncodeMap[unicode] {
                // lazy append since string append may require memory reallocation
                // move unbuffered characters over to the result buffer
                str.append(String(unicodes[leftIndex..<currentIndex]))

                // append entity to result buffer
                str.append(entity)

                // move left index
                leftIndex = nextIndex
            }
            else if !unicode.isASCII
                || unicode.isTagSyntax
                || unicode.isAttributeSyntax {
                // unicode is not a named character, and is either
                // not an ASCII character, or is an unsafe ASCII character
                // lazy append since string append may require memory reallocation
                // move unbuffered characters over to the result buffer
                str.append(String(unicodes[leftIndex..<currentIndex]))

                // append unicode value to result buffer
                let codeStr = decimal ? String(unicode, radix: 10) :
                    "x" + String(unicode, radix: 16, uppercase: true)

                str.append("&#" + codeStr + ";")

                // move left index
                leftIndex = nextIndex
            }

            currentIndex = nextIndex
        }

        if str == "" {
            // no unsafe unicode found
            // return string as it is
            return self
        }

        // append rest of string to result buffer
        str.append(String(unicodes[leftIndex..<unicodes.endIndex]))

        return str
    }

    /// Return string as HTML unescaped by replacing HTML named character entities
    /// with their unicode character equivalents.
    /// For example, this function turns
    /// `"&lt;script&gt;alert(&quot;abc&quot;)&lt;/script&gt;"`
    /// into
    /// `"<script>alert(\"abc\")</script>"`
    /// - parameter strict: Specifies if escapes MUST always end with `;`.
    /// *Optional*. Defaults to true.
    public func htmlUnescape(strict: Bool = true) -> String {
        let unicodes = self.unicodeScalars

        // result buffer
        var str: String = ""

        // entity buffer
        var entity: String = ""

        // current parse state
        var state = EntityParseState.Invalid

        // indices for substringing and iterating
        var leftIndex = unicodes.startIndex
        var currentIndex = leftIndex
        var ampersandIndex = unicodes.endIndex

        let reset = {
            entity = ""
            state = .Invalid
            ampersandIndex = unicodes.endIndex
        }

        while (currentIndex < unicodes.endIndex) {
            var nextIndex = unicodes.index(after: currentIndex)
            let unicode = unicodes[currentIndex].value

            // nondeterminstic finite automaton for parsing entity
            // NOTE: While all entities begin with &,
            // not all HTML5 named character references end with ;,
            // nor do numeric entities, hex or dec, have to end with ;
            switch state {
            case .Invalid:
                if unicode.isAmpersand {
                    // start of a possible entity of unknown type
                    state = .Unknown
                    ampersandIndex = currentIndex
                }
            case .Unknown:
                // parsed an & unicode,
                // need to determine type of entity
                if unicode.isHash {
                    // entity can only be a number type
                    state = .Number
                }
                else if unicode.isAlpha {
                    // entity can only be named character reference type
                    state = .Named
                    entity.append(String(unicodes[currentIndex]))
                }
                else {
                    // false alarm, not an entity; reset state
                    reset()
                }
            case .Number:
                // parsed a # unicode,
                // need to determine dec or hex
                if unicode.isX {
                    // entity can only be hexadecimal type
                    state = .Hex
                }
                else if unicode.isNumeral {
                    // entity can only be decimal type
                    state = .Dec
                    entity.append(String(unicodes[currentIndex]))
                }
                else {
                    reset()
                }
            case .Dec, .Hex, .Named:
                // lookahead one unicode to help decide next action
                let lookahead: UInt32? = nextIndex == unicodes.endIndex
                    ? nil : unicodes[nextIndex].value

                var isEndOfEntity = false

                if unicode.isValidEntityUnicode(for: state) {
                    // buffer current unicode
                    entity.append(String(unicodes[currentIndex]))

                    if let lookahead = lookahead {
                        // lookahead is not empty
                        isEndOfEntity = lookahead.isSemicolon
                            || !strict && !lookahead.isValidEntityUnicode(for: state)
                    }
                    else {
                        // lookahead is empty
                        isEndOfEntity = !strict
                    }
                }
                else {
                    // strict parsing, but encountered something
                    // other than ; or hexadecimal numeral
                    reset()
                }

                if isEndOfEntity {
                    if let lookahead = lookahead, lookahead.isSemicolon {
                        // consume the ; by moving nextIndex by one so that
                        ///nextIndex is pointing to the unicode after the ;
                        nextIndex = unicodes.index(after: nextIndex)

                        if state == .Named {
                            entity.append(";")
                        }
                    }

                    var code: UInt32? = nil

                    switch state {
                    case .Dec:
                        code = UInt32(entity, radix: 10)
                    case .Hex:
                        code = UInt32(entity, radix: 16)
                    case .Named:
                        code = html4NamedCharactersDecodeMap["&" + entity]
                    default:
                        break
                    }

                    if let code = code,
                        let unicodeScalar = UnicodeScalar(code) {
                        // reached end of entity
                        // move unbuffered unicodes over to the result buffer
                        str.append(String(unicodes[leftIndex..<ampersandIndex]))

                        // append unescaped character to result buffer
                        str.append(Character(unicodeScalar))

                        // move left index since we have buffered everything
                        // up to and including the current entity
                        leftIndex = nextIndex
                    }

                    // even if entity wasn't unescapable, reset since it is
                    // end of entity
                    reset()
                }
            }

            // move currentIndex to the position of the next unicode to be consumed
            currentIndex = nextIndex
        }
        
        if str == "" {
            // no unescapable entity found
            // return string as it is
            return self
        }
        
        // append rest of string to result buffer
        str.append(String(unicodes[leftIndex..<unicodes.endIndex]))
        
        return str
    }
}
