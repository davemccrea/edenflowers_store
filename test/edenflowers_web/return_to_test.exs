defmodule EdenflowersWeb.Auth.ReturnToTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.Auth.ReturnTo

  describe "safe_path/1" do
    test "accepts path-only same-origin URLs" do
      assert ReturnTo.safe_path("/account") == "/account"
      assert ReturnTo.safe_path("/order/abc123") == "/order/abc123"
      assert ReturnTo.safe_path("/store?category=bouquets") == "/store?category=bouquets"
      assert ReturnTo.safe_path("/") == "/"
    end

    test "rejects external and protocol-relative URLs" do
      assert ReturnTo.safe_path("https://evil.example.com/steal") == nil
      assert ReturnTo.safe_path("//evil.example.com/steal") == nil
      assert ReturnTo.safe_path("http://localhost:4000/account") == nil
    end

    test "rejects relative paths without a leading slash" do
      assert ReturnTo.safe_path("account") == nil
      assert ReturnTo.safe_path("../etc/passwd") == nil
    end

    test "rejects sign-in, sign-out, auth, and password-reset paths" do
      assert ReturnTo.safe_path("/sign-in") == nil
      assert ReturnTo.safe_path("/sign-in?foo=bar") == nil
      assert ReturnTo.safe_path("/sign-out") == nil
      assert ReturnTo.safe_path("/auth/user/google") == nil
      assert ReturnTo.safe_path("/password-reset") == nil
    end

    test "does not reject paths that merely share a prefix with auth routes" do
      assert ReturnTo.safe_path("/sign-in-and-share") == "/sign-in-and-share"
      assert ReturnTo.safe_path("/authentication-guide") == "/authentication-guide"
    end

    test "rejects non-binary values" do
      assert ReturnTo.safe_path(nil) == nil
      assert ReturnTo.safe_path(123) == nil
      assert ReturnTo.safe_path(%{}) == nil
    end
  end
end
