// Solidity language definition for highlight.js v10 (mdBook's bundled version)
hljs.registerLanguage("solidity", function(hljs) {
  var SOL_KEYWORDS = {
    keyword:
      'pragma solidity import is abstract contract interface library ' +
      'using for struct enum event error modifier constructor function ' +
      'receive fallback if else while do for break continue return ' +
      'throw emit revert try catch assembly let switch case default ' +
      'delete new mapping returns memory storage calldata payable ' +
      'public private internal external constant immutable pure view ' +
      'virtual override indexed anonymous unchecked type',
    type:
      'address bool string bytes byte int uint ' +
      'int8 int16 int24 int32 int40 int48 int56 int64 int72 int80 int88 int96 ' +
      'int104 int112 int120 int128 int136 int144 int152 int160 int168 int176 ' +
      'int184 int192 int200 int208 int216 int224 int232 int240 int248 int256 ' +
      'uint8 uint16 uint24 uint32 uint40 uint48 uint56 uint64 uint72 uint80 uint88 uint96 ' +
      'uint104 uint112 uint120 uint128 uint136 uint144 uint152 uint160 uint168 uint176 ' +
      'uint184 uint192 uint200 uint208 uint216 uint224 uint232 uint240 uint248 uint256 ' +
      'bytes1 bytes2 bytes3 bytes4 bytes5 bytes6 bytes7 bytes8 bytes9 bytes10 ' +
      'bytes11 bytes12 bytes13 bytes14 bytes15 bytes16 bytes17 bytes18 bytes19 bytes20 ' +
      'bytes21 bytes22 bytes23 bytes24 bytes25 bytes26 bytes27 bytes28 bytes29 bytes30 ' +
      'bytes31 bytes32 fixed ufixed',
    literal:
      'true false wei gwei ether seconds minutes hours days weeks years',
    built_in:
      'msg block tx abi this super selfdestruct now gasleft blockhash ' +
      'keccak256 sha256 ripemd160 ecrecover addmod mulmod ' +
      'require assert revert'
  };

  var SOL_NUMBER = {
    className: 'number',
    variants: [
      { begin: '\\b(0[xX][a-fA-F0-9](_?[a-fA-F0-9])*)' },
      { begin: '\\b(\\d+(_\\d+)*(\\.\\d+(_\\d+)*)?|\\.\\d+(_\\d+)*)([eE][-+]?\\d+(_\\d+)*)?' }
    ],
    relevance: 0
  };

  var SOL_FUNC = {
    className: 'function',
    beginKeywords: 'function modifier event error constructor',
    end: /[{;]/,
    excludeEnd: true,
    contains: [
      hljs.inherit(hljs.TITLE_MODE, { begin: /[A-Za-z_$][A-Za-z0-9_$]*/ }),
      {
        className: 'params',
        begin: /\(/,
        end: /\)/,
        contains: [
          hljs.C_LINE_COMMENT_MODE,
          hljs.C_BLOCK_COMMENT_MODE,
          SOL_NUMBER,
          { className: 'string', begin: /"/, end: /"/ },
          { className: 'string', begin: /'/, end: /'/ }
        ]
      },
      hljs.C_LINE_COMMENT_MODE,
      hljs.C_BLOCK_COMMENT_MODE
    ]
  };

  return {
    aliases: ['sol'],
    keywords: SOL_KEYWORDS,
    contains: [
      // Pragma
      {
        className: 'meta',
        begin: /pragma/,
        end: /;/,
        contains: [
          { className: 'meta-string', begin: /solidity/ },
          hljs.C_LINE_COMMENT_MODE
        ]
      },
      // Import
      {
        className: 'meta',
        begin: /import/,
        end: /;/,
        contains: [
          { className: 'string', begin: /"/, end: /"/ },
          { className: 'string', begin: /'/, end: /'/ }
        ]
      },
      hljs.C_LINE_COMMENT_MODE,
      hljs.C_BLOCK_COMMENT_MODE,
      hljs.APOS_STRING_MODE,
      hljs.QUOTE_STRING_MODE,
      SOL_NUMBER,
      SOL_FUNC,
      // Contract/interface/library declarations
      {
        className: 'class',
        beginKeywords: 'contract interface library struct enum',
        end: /\{/,
        excludeEnd: true,
        contains: [
          hljs.inherit(hljs.TITLE_MODE, { begin: /[A-Za-z_$][A-Za-z0-9_$]*/ }),
          hljs.C_LINE_COMMENT_MODE,
          hljs.C_BLOCK_COMMENT_MODE
        ]
      },
      // NatSpec documentation comments
      {
        className: 'comment',
        begin: /\/\/\//,
        end: /$/,
        contains: [
          { className: 'doctag', begin: /@\w+/ }
        ]
      }
    ]
  };
});

// Re-highlight all Solidity code blocks after registration
(function() {
  document.querySelectorAll('code.language-solidity').forEach(function(block) {
    hljs.highlightBlock(block);
  });
})();
