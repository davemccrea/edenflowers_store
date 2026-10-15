defmodule Edenflowers.WeddingEnquiry.SendEmailsTest do
  use Edenflowers.DataCase, async: true
  import Swoosh.TestAssertions

  alias Edenflowers.WeddingEnquiry.SendEmails

  test "the couple gets a copy greeting them by first name, bcc Jennie" do
    assert {:ok, _} =
             perform_job(SendEmails, %{
               "name" => "Anna Svensson",
               "email" => "anna@example.com",
               "wedding_date" => "2027-06-12",
               "venue" => "Smedsby",
               "guests" => nil,
               "message" => nil,
               "selection" => ["1 × Bridal bouquet"],
               "estimate" => "€110–€190",
               "locale" => "en-GB"
             })

    from_address = Application.fetch_env!(:edenflowers, :mailer_from_address)

    assert_email_sent(fn email ->
      refute email.text_body =~ "Number of guests"
      assert email.to == [{"Anna Svensson", "anna@example.com"}]
      assert email.bcc == [from_address]
      assert email.text_body =~ "Hi Anna,"
      assert email.text_body =~ "12/06/2027"
      assert email.text_body =~ "- 1 × Bridal bouquet"
      assert email.text_body =~ "Estimate: €110–€190"
    end)
  end
end
