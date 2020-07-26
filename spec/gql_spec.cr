require "./spec_helper"
require "http/client"

describe GQL do
  describe ".graphql" do
    context "simple query" do
      it "returns the graphql query" do
        SimpleQuery.graphql.should eq(<<-GQL)
        {
          id
          legacyId
        }
        GQL
      end
    end

    context "nested query" do
      it "returns the graphql query" do
        RootQuery.graphql.should eq(<<-GQL)
        {
          rootQuery(attributes: { first: $first }) {
            id
            nested {
              id
              costCents
              costInDollars
            }
          }
        }
        GQL
      end
    end
  end

  describe ".post" do
    it "sends a query" do
      client = FakeHttpClient.new(
        expected_body: {
          query:     "query($first: Int, $after: String, ) #{RootQuery.graphql}",
          variables: {first: nil, after: nil},
        }.to_json
      )
      RootQuery.post(client)
    end

    it "parses the result" do
      client = FakeHttpClient.new(
        response_body: %{{
          "data": {
            "rootQuery": {
              "id": "MYID",
              "nested": {
                "id": "SomeGlobalID",
                "costCents": 123,
                "costInDollars": 12.34
              }
            }
          }
        }})
      data = RootQuery.post(client)

      data.should be_a RootQuery
      data.try(&.root_query.id).should eq "MYID"
      data.try(&.root_query.nested.id).should eq "SomeGlobalID"
      data.try(&.root_query.nested.cost_cents).should eq 123
      data.try(&.root_query.nested.cost_in_dollars).should eq 12.34
    end
  end
end

class FakeHttpClient
  def initialize(@expected_body : String? = nil, @response_status = 200, @response_body = "{}")
  end

  def post(url : String, headers : HTTP::Headers, body : String)
    url.should eq "/graphql"
    headers.should eq HTTP::Headers{"Content-Type" => "application/json"}
    body.should eq @expected_body if @expected_body
    HTTP::Client::Response.new(status_code: @response_status, body: @response_body)
  end
end

@[GQL::Serializable::Options]
class SimpleQuery
  include GQL::Serializable
  property id : String
  property legacy_id : Int64
end

@[GQL::Serializable::Options(query_args: {first: Int, after: String})]
class RootQuery
  include GQL::Serializable

  class NestedQuery
    include GQL::Serializable
    property id : String
    property cost_cents : Int64
    property cost_in_dollars : Float64
  end

  class RootQuery
    include GQL::Serializable
    property id : String
    @[GQL::Field(sub: true)]
    property nested : NestedQuery
  end

  @[GQL::Field(graphql: "rootQuery(attributes: { first: $first })", sub: true)]
  property root_query : ::RootQuery::RootQuery
end
