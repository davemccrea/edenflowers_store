defmodule EdenflowersWeb.NewsletterSignupFormTest do
  use EdenflowersWeb.ConnCase, async: true

  import PhoenixTest

  describe "Newsletter signup form" do
    test "submitting a valid email shows the success message", %{conn: conn} do
      conn
      |> visit("/")
      |> fill_in("Email Address", with: "test@example.com")
      |> submit()
      |> assert_has("p", text: "Thanks! Your 15% off code is on its way to your inbox.")
    end
  end
end
