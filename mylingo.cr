require "lingo"
require "digest/md5"

module GQL2
  class QueryParser < Lingo::Parser
    rule(:whitespace) { match(/\s+/) }
    rule(:name) { match(/[a-z][a-zA-Z]*/) }
    rule(:args) { str("(") >> match(/[^)]*/) >> str(")") }
    rule(:field) { name.named(:field_name) >> args.maybe >> whitespace.maybe >> nested.named(:nested).maybe }
    rule(:field_whitespace) { field >> whitespace.maybe }
    rule(:nested) { str("{") >> whitespace.maybe >> field_whitespace.repeat.maybe >> whitespace.maybe >> str("}") }
    rule(:query) { str("query") >> whitespace.maybe >> args.maybe}
    rule(:full) { whitespace.maybe >> query >> whitespace.maybe >> nested.named(:outer).maybe >> whitespace.maybe}
    root(:full)
  end

  class QueryVisitor < Lingo::Visitor
    # Set up an accumulator
    getter :path, :prefix, :code, :fields, :types, :md5
    setter :prefix, :code, :fields, :types, :md5
    def initialize
      @path = [""] of String
      @prefix = "  "
      @code = ""
      @fields = [[] of String] of Array(String)
      @types = Hash(String, String).new
      @md5 = ""
    end

    enter(:outer) {
      visitor.md5 = Digest::MD5.hexdigest(node.full_value.to_s)
      visitor.path[0] = "Outer#{visitor.md5}"
      visitor.code += "class Outer#{visitor.md5}\n"
    }

    exit(:outer) {
      visitor.fields.pop.each do |field|
        type = visitor.types.fetch(field, "JSON::ANY::Type")
        visitor.code += "#{visitor.prefix}[JSON::Field(key: \"#{field}\")]\n"
        visitor.code += "#{visitor.prefix}property #{field.underscore} : #{type}\n"
      end
      visitor.code += "  class Inner#{visitor.md5}\n"
      visitor.code += "    property data Outer#{visitor.md5}\n"
      visitor.code += "    property errors JSON::ANY::Type\n"
      visitor.code += "  end\n"
      visitor.code += "end\n"
    }

    enter(:field_name) {
      visitor.path[visitor.path.size - 1] = node.full_value.to_s
      visitor.fields[visitor.fields.size - 1] << node.full_value.to_s
    }

    enter(:nested) {
      visitor.types[visitor.path.last] = visitor.path.last.camelcase
      visitor.code += "#{visitor.prefix}class #{visitor.path.last.camelcase}\n#{visitor.prefix}  include JSON::Serializable\n"
      visitor.path << ""
      visitor.prefix += "  "
      visitor.fields << [] of String
    }

    exit(:nested) {
      visitor.path.pop

      fields = visitor.fields.pop
      fields.each do |field|
        type = visitor.types.fetch(field, "JSON::ANY::Type")
        visitor.code += "#{visitor.prefix}[JSON::Field(key: \"#{field}\")]\n"
        visitor.code += "#{visitor.prefix}property #{field.underscore} : #{type}\n"
      end

      visitor.prefix = visitor.prefix.chomp("  ")
      visitor.code += "#{visitor.prefix}end\n"
    }
  end

  def self.parse(str)
    ast = QueryParser.new.parse(str)
    visitor = QueryVisitor.new
    visitor.visit(ast)
    { code: visitor.code, md5: visitor.md5 }
  end
end

{% begin %}
{% data = GQL2.parse(%{
  query($first: Int) {
    advertSearch {
      adverts(first: $first) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          title
          variants {
            nodes {
              id
              label
              barcode
              countOnHand
            }
          }
        }
      }
    }
  }
}) %}
{{ data[:code] }}
pp Outer{{data[:md5]}}::Inner{{data[:md5]}}.new
{% end %}
