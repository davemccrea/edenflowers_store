defmodule Edenflowers.Accounts.Workers.SendOtpEmailTest do
  use Edenflowers.DataCase
  import Swoosh.TestAssertions

  alias Edenflowers.Accounts.Workers.SendOtpEmail

  test "sends a plain-text email containing the OTP code" do
    assert {:ok, _} =
             perform_job(SendOtpEmail, %{
               "email" => "user@example.com",
               "otp_code" => "ABC123",
               "locale" => "en-GB"
             })

    assert_email_sent(fn email ->
      assert email.to == [{"", "user@example.com"}]
      assert email.subject =~ "Eden Flowers"
      assert email.text_body =~ "ABC123"
      assert email.html_body in [nil, ""]
    end)
  end

  test "honours the locale passed in the job args" do
    assert {:ok, _} =
             perform_job(SendOtpEmail, %{
               "email" => "user@example.com",
               "otp_code" => "ABC123",
               "locale" => "fi"
             })

    assert_email_sent(fn email ->
      assert email.text_body =~ "ABC123"
    end)
  end

  test "does not leak job's locale into the caller's process state" do
    Gettext.put_locale(EdenflowersWeb.Gettext, "en")

    assert {:ok, _} =
             perform_job(SendOtpEmail, %{
               "email" => "user@example.com",
               "otp_code" => "ABC123",
               "locale" => "fi"
             })

    assert Gettext.get_locale(EdenflowersWeb.Gettext) == "en"
  end
end
