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
          number string ustring any unknown never unsafe default namespace
          _G _VERSION assert assert_eq collectgarbage dofile error getmetatable
          ipairs load loadfile next pairs pcall print rawequal rawget rawlen
          rawset select setmetatable tonumber tostring xpcall typeof
        )
      end

      def current_string
        @string_register ||= StringRegister.new
      end

      state :root do
        # fuse allows a file to start with a shebang
        rule %r(#!(.*?)$), Comment::Preproc
        rule %r//, Text, :base
      end

      ascii = /\d{1,3}/i
      hex = /[0-9a-f]/i
      escapes = %r(
        \\ ([nrt\\"'0\s] | #{ascii} | x#{hex}{2} | u#{hex}{4} | U#{hex}{8})
      )xm

      state :base do
        rule %r(--\[(=*)\[.*?\]\1\])m, Comment::Multiline
        rule %r(--.*$), Comment::Single

        num = /[0-9_]/
        rule %r((?i)(#{num}*\.#{num}+|#{num}+\.#{num}*)(e[+-]?+)?'), Num::Float
        rule %r((?i)#{num}+e[+-]?\d+), Num::Float
        rule %r((?i)0b[01_]*), Num::Bin
        rule %r((?i)0x[0-9a-fA-F_]*), Num::Hex
        rule %r(#{num}+), Num::Integer

        rule %r(\n), Text
        rule %r([^\S\n]), Text

        rule %r((==|!=|<=|>=|\.\.\.|\?|[&|!\(<<\)\(>>\)]|[=+\-*/%^<>#])), Operator
        rule %r([\[\]\{\}\(\)\.,:;]), Punctuation
        rule %r((and|or|not)\b), Operator::Word

        rule %r((break|do|else|elseif|end|for|if|in|repeat|return|then|until|while)\b), Keyword
        rule %r((as|enum|struct|type|trait|impl|union|import|from|export|match|when|is|try|catch|finally|pub)\b), Keyword
        rule %r((const|let|static)\b), Keyword::Declaration
        rule %r((true|false|nil)\b), Keyword::Constant

        rule %r((function|fn)\b), Keyword, :function_name


        rule %r/([u]{0,1})('|")/i do |m|
          token Str
          current_string.register type: m[1].downcase, delim: m[2]
          push :generic_string
        end

        # raw strings
        rule %r/(u?r)(#*)(["'])(.|\n)*?(\3)(\2)/, Str

        # identifiers
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

      state :generic_string do
        mixin :generic_escape

        rule %r/['"]/ do |m|
          token Str
          if current_string.delim? m[0]
            current_string.remove
            pop!
          end
        end

        rule %r/\${/ do |m|
            token Str::Interpol
            push :generic_interpol
        end

        rule %r/[^"\\]+/m, Str
      end

      state :generic_escape do
        rule escapes, Str::Escape
      end

      state :generic_interpol do
        rule %r/[^${}]+/ do |m|
          recurse m[0]
        end
        rule %r/\${/, Str::Interpol, :generic_interpol
        rule %r/}/, Str::Interpol, :pop!
      end

      class StringRegister < Array
        def delim?(delim)
          self.last[1] == delim
        end

        def register(type: "u", delim: "'")
          self.push [type, delim]
        end

        def remove
          self.pop
        end

        def type?(type)
          self.last[0].include? type
        end
      end

      private_constant :StringRegister
    end
  end
end
