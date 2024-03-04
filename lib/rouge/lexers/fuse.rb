# -*- coding: utf-8 -*- #
# frozen_string_literal: true

module Rouge
  module Lexers
    class Fuse < RegexLexer
      title "Fuse"
      desc "Fuse (https://fuse-lang.github.io)"
      tag 'fuse'
      filenames '*.fuse', '*.fu'

      mimetypes 'text/x-fuse', 'application/x-fuse'

      option :function_highlighting, 'Whether to highlight builtin functions (default: true)'
      option :disabled_modules, 'builtin modules to disable'

      def initialize(opts={})
        @function_highlighting = opts.delete(:function_highlighting) { true }
        @disabled_modules = opts.delete(:disabled_modules) { [] }
        super(opts)
      end

      def self.detect?(text)
        return true if text.shebang? 'fuse'
      end

      def self.builtins
        @builtins ||= Set.new %w(
          number string ustring any unknown never default namespace
          _G _VERSION assert collectgarbage dofile error getmetatable
          ipairs load loadfile next pairs pcall print rawequal rawget rawlen
          rawset select setmetatable tonumber tostring xpcall
        )
      end

      state :root do
        # fuse allows a file to start with a shebang
        rule %r(#!(.*?)$), Comment::Preproc
        rule %r//, Text, :base
      end

      state :base do
        rule %r(--\[(=*)\[.*?\]\1\])m, Comment::Multiline
        rule %r(--.*$), Comment::Single

        rule %r((?i)(\d*\.\d+|\d+\.\d*)(e[+-]?\d+)?'), Num::Float
        rule %r((?i)\d+e[+-]?\d+), Num::Float
        rule %r((?i)0x[0-9a-f]*), Num::Hex
        rule %r(\d+), Num::Integer

        rule %r(\n), Text
        rule %r([^\S\n]), Text

        rule %r((==|~=|<=|>=|\.\.\.|\.\.|[=+\-*/%^<>#])), Operator
        rule %r([\[\]\{\}\(\)\.,:;]), Punctuation
        rule %r((and|or|not)\b), Operator::Word

        rule %r((break|do|else|elseif|end|for|if|in|repeat|return|then|until|while)\b), Keyword
        rule %r((as|struct|type|trait|impl|import|from|export|match|when|is|try|catch|finally)\b), Keyword
        rule %r((const|let|global)\b), Keyword::Declaration
        rule %r((true|false|nil)\b), Keyword::Constant

        rule %r((function|fn)\b), Keyword, :function_name

        rule %r/u{0,1}r(#*)("|').*?\2\1/m, Str
        rule %r(u{0,1}'), Str::Single, :escape_sqs
        rule %r(u{0,1}"), Str::Double, :escape_dqs

        rule %r([A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)?) do |m|
          name = m[0]
          if name == "gsub"
            token Name::Builtin
            push :gsub
          elsif self.class.builtins.include?(name)
            token Name::Builtin
          elsif name =~ /\./
            a, b = name.split('.', 2)
            token Name, a
            token Punctuation, '.'
            token Name, b
          else
            token Name
          end
        end

      end

      state :function_name do
        rule %r/\s+/, Text
        rule %r((?:([A-Za-z_][A-Za-z0-9_]*)(\.))?([A-Za-z_][A-Za-z0-9_]*)) do
          groups Name::Class, Punctuation, Name::Function
          pop!
        end
        # inline function
        rule %r(\(), Punctuation, :pop!
      end

      state :gsub do
        rule %r/\)/, Punctuation, :pop!
        rule %r/[(,]/, Punctuation
        rule %r/\s+/, Text
        rule %r/"/, Str::Regex, :regex
      end

      state :regex do
        rule %r(") do
          token Str::Regex
          goto :regex_end
        end

        rule %r/\[\^?/, Str::Escape, :regex_group
        rule %r/\\./, Str::Escape
        rule %r{[(][?][:=<!]}, Str::Escape
        rule %r/[{][\d,]+[}]/, Str::Escape
        rule %r/[()?]/, Str::Escape
        rule %r/./, Str::Regex
      end

      state :regex_end do
        rule %r/[$]+/, Str::Regex, :pop!
        rule(//) { pop! }
      end

      state :regex_group do
        rule %r(/), Str::Escape
        rule %r/\]/, Str::Escape, :pop!
        rule %r/(\\)(.)/ do |m|
          groups Str::Escape, Str::Regex
        end
        rule %r/./, Str::Regex
      end

      state :escape_sqs do
        mixin :string_escape
        mixin :sqs
      end

      state :escape_dqs do
        mixin :string_escape
        mixin :dqs
      end

      state :string_escape do
        rule %r(\\([nrt\\"'0\s]|\d{1,3}))xm, Str::Escape
      end

      state :sqs do
        rule %r('), Str::Single, :pop!
        rule %r/[^'\\]+/m, Str::Single
      end

      state :dqs do
        rule %r("), Str::Double, :pop!
        rule %r/[^"\\]+/m, Str::Double
      end
    end
  end
end
