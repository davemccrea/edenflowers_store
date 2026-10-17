defmodule EdenflowersWeb.PaymentLink do
  @moduledoc "The URL a customer opens to pay an order or course booking online."
  use EdenflowersWeb, :verified_routes

  def url_for(%Edenflowers.Courses.CourseRegistration{payment_link_token: token}) when is_binary(token),
    do: url(~p"/courses/pay/#{token}")

  def url_for(%{payment_link_token: token}) when is_binary(token), do: url(~p"/pay/#{token}")
end
