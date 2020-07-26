require "lingo"
require "digest/md5"

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
  getter :path, :prefix, :code
  setter :prefix, :code
  def initialize
    @path = [""] of String
    @prefix = "  "
    @code = ""
  end

  enter(:outer) {
    outer = "Outer#{Digest::MD5.hexdigest(node.full_value.to_s)}"
    visitor.path[0] = outer
    visitor.code += "class #{outer}\n"
  }

  exit(:outer) {
    visitor.code += "end\n"
  }

  enter(:field_name) {
    # puts "ENTER: #{node.full_value}"
    visitor.code += "#{visitor.prefix}property #{node.full_value.to_s.underscore} : JSON::ANY::Type\n"
    visitor.path[visitor.path.size - 1] = node.full_value.to_s
  }

  enter(:nested) {
    visitor.code += "\n#{visitor.prefix}class #{visitor.path.last.camelcase}\n#{visitor.prefix}  include JSON::Serializable\n"
    visitor.path << ""
    visitor.prefix += "  "
  }

  exit(:nested) {
    visitor.prefix = visitor.prefix.chomp("  ")
    visitor.code += "#{visitor.prefix}end\n"
    visitor.path.pop
  }
end

ast = QueryParser.new.parse(%{
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
})
visitor = QueryVisitor.new
visitor.visit(ast)
puts "=====\n#{visitor.code}\n"
