defmodule Edenflowers.Email.PreviewsTest do
  use ExUnit.Case, async: true

  alias Edenflowers.Email
  alias Edenflowers.Email.Previews

  # The error alert goes to the developer, not a customer, so Jennie has nothing to proofread.
  @not_previewed [:error_alert]

  test "every customer email has a preview" do
    builders = Email.__info__(:functions) |> Enum.map(fn {name, _arity} -> name end) |> MapSet.new()
    previewed = MapSet.new(Previews.all("en-GB"), fn {_email_type, _scenario, builder, _email} -> builder end)

    assert MapSet.difference(builders, previewed) == MapSet.new(@not_previewed)
  end

  test "renders in the requested language" do
    assert [{"Order confirmation", _scenario, :order_confirmation, email} | _] = Previews.all("fi")
    assert email.text_body =~ "lauantaina 14.11.2026"
  end
end
