defmodule Edenflowers.SeedsTest do
  use Edenflowers.DataCase, async: false

  import ExUnit.CaptureIO
  import Mox

  @moduletag :typst
  @moduletag capture_log: true

  test "dev fixtures seed successfully on an empty database" do
    stub(Edenflowers.External.StripeAPI.Mock, :retrieve_payment_intent, fn _ -> {:error, :not_found} end)

    capture_io(fn -> Code.eval_file("priv/repo/seeds.exs") end)

    assert Ash.count!(Edenflowers.Orders.Order, authorize?: false) > 0
    assert Ash.count!(Edenflowers.Payments.Invoice, authorize?: false) > 0
  end
end
