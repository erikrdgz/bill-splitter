ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  # Creates a split the way a real organizer does, through the quick split form,
  # so it belongs to this test's browser cookie. Building one with Split.create!
  # would give it no owner this session can prove, and every later request would
  # correctly 404.
  def create_split(amount: "100", people_count: 3)
    post splits_url, params: { split: { amount: amount, people_count: people_count } }

    Split.find(response.location[%r{/splits/(\d+)}, 1])
  end

  # Counts the SELECTs a block runs, so an N+1 can be asserted against rather
  # than noticed in production. SCHEMA and TRANSACTION rows are the adapter
  # talking to itself, not the page's doing.
  def count_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)

    count
  end
end
