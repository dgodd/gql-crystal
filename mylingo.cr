require "lingo"

class QueryParser < Lingo::Parser
  rule(:whitespace) { match(/\s+/) }
  rule(:name) { match(/[a-z][a-zA-Z]*/) }
  rule(:args) { str("(") >> match(/[^)]*/) >> str(")") }
  rule(:field) { name >> args.maybe >> whitespace.maybe >> nested.maybe }
  rule(:nested) { str("{") >> whitespace.maybe >> field.repeat.maybe >> whitespace.maybe >> str("}") }
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
      }
    }
  }
})

# pp QueryParser.new.parse(%{query($first: Int) {
#     advertSearch {
#       adverts(first: $first) {
#         pageInfo {
#           hasNextPage
#         }
#         nodes {
#           id
#           title
#           variants {
#             nodes {
#               id
#               label
#               barcode
#               countOnHand
#             }
#           }
#         }
#       }
#     }
#   }
# })
