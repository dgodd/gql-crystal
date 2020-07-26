require "lingo"

class QueryParser < Lingo::Parser
  rule(:whitespace) { match(/\s+/) }
  rule(:name) { match(/[a-z][a-zA-Z]*/) }
  rule(:args) { str("(") >> match(/[^)]*/) >> str(")") }
  rule(:field) { name.named(:field_name) >> args.named(:field_args).maybe >> whitespace.maybe >> nested.maybe }
  rule(:field_whitespace) { field >> whitespace.maybe }
  rule(:nested) { str("{") >> whitespace.maybe >> field_whitespace.repeat.maybe >> whitespace.maybe >> str("}") }
  rule(:query) { str("query") >> whitespace.maybe >> args.maybe}
  rule(:full) { whitespace.maybe >> query >> whitespace.maybe >> nested.maybe >> whitespace.maybe}
  root(:full)
end

pp QueryParser.new.parse(%{
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
