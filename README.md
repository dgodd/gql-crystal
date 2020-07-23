# GQL

[![Build Status](https://travis-ci.org/dgodd/gql-crystal.svg?branch=main)](https://travis-ci.org/dgodd/gql-crystal)

Creates simple Graphql clients

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     gql:
       github: dgodd/gql-crystal
   ```

2. Run `shards install`

## Usage

```crystal
require "http/client"
require "gql"

@[GQL::Serializable::Options(root: true, query_args: {updatedSince: ISO8601DateTime, first: Int, after: String})]
class AdvertSearch
  include GQL::Serializable

  class PageInfo
    include GQL::Serializable

    property has_next_page : Bool
    property end_cursor : String
  end

  class Advert
    include GQL::Serializable

    property id : String
    property legacy_id : Int64
    property title : String
    property updated_at : String
  end

  class Adverts
    include GQL::Serializable

    @[GQL::Field(sub: true)]
    property page_info : PageInfo
    @[GQL::Field(type: AdvertSearch::Advert, sub: true)]
    property nodes : Array(Advert)
  end

  class AdvertSearch
    include GQL::Serializable

    @[GQL::Field(graphql: "adverts(first: $first, after: $after)", sub: true)]
    property adverts : Adverts
  end

  @[GQL::Field(graphql: "advertSearch(attributes: { updatedSince: $updatedSince })", sub: true)]
  property advert_search : AdvertSearch

  def page_info
    advert_search.adverts.page_info
  end
end

client = HTTP::Client.new("marketplacer.lvh.me", port: 3000, tls: false)
pp AdvertSearch.post(client, { updatedSince: "2020-06-24T08:45:14+10:00", first: 10 })
data = nil
loop do
  after = data.page_info.end_cursor if data
  data = AdvertSearch.post(client, updated_since: "2020-06-24T08:45:14+10:00", first: 10, after: after)
  pp data
  break unless data && data.page_info.has_next_page
end
```

## Development

```
crystal spec
```

## Contributing

1. Fork it (<https://github.com/your-github-user/gql-crystal/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Dave Goddard](https://github.com/dgodd) - creator and maintainer
