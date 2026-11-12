defmodule Edenflowers.Orders.ShopNotice do
  @moduledoc """
  What Jennie is told, by email and push: one line saying what happened, and
  where it is in the admin. A notice is `{:new, order}`, `{:new, subscription}`,
  `{:new, registration}`, for a course booking a customer paid for,
  `{:reminder, order}`, for an order with a time that starts within the hour,
  or `{:cancelled, order}` or `{:cancelled, subscription}`, for one its
  customer cancelled.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Subscription

  @doc "Serializes the notice kind and record ID into arguments for the notification workers."
  def args({kind, %Order{id: id}}), do: %{"notice" => to_string(kind), "order_id" => id}
  def args({kind, %Subscription{id: id}}), do: %{"notice" => to_string(kind), "subscription_id" => id}
  def args({kind, %CourseRegistration{id: id}}), do: %{"notice" => to_string(kind), "registration_id" => id}

  def fetch!(%{"notice" => kind} = args), do: {String.to_existing_atom(kind), record!(args)}

  defp record!(%{"order_id" => id}), do: Orders.get_order_by_id!(id, authorize?: false)
  defp record!(%{"subscription_id" => id}), do: Orders.get_subscription!(id, authorize?: false)
  defp record!(%{"registration_id" => id}), do: Courses.get_registration_by_id!(id, authorize?: false)

  @doc "Builds the notification title in `locale`; the caller must also set Gettext to that locale."
  def title(notice, locale)

  def title({:new, %Order{} = order}, _locale) do
    cond do
      order.fulfillment_date != Edenflowers.ShopTime.today() -> ~t"New order #{order.order_reference}"
      order.fulfillment_method == :pickup -> ~t"Pickup for today #{order.order_reference}"
      true -> ~t"Delivery for today #{order.order_reference}"
    end
  end

  def title({:new, %Subscription{}}, _locale), do: ~t"New subscription"

  def title({:new, %CourseRegistration{} = registration}, _locale),
    do: ~t"New course booking #{registration.reference}"

  def title({:cancelled, %Order{} = order}, _locale),
    do: ~t"Order #{reference = order.order_reference} cancelled by the customer"

  def title({:cancelled, %Subscription{}}, _locale), do: ~t"Subscription cancelled by the customer"

  def title({:reminder, %Order{} = order}, locale) do
    time = Format.fulfillment_time(order, locale)

    if order.fulfillment_method == :pickup,
      do: ~t"Pickup #{time}, order #{order.order_reference}",
      else: ~t"Delivery #{time}, order #{order.order_reference}"
  end

  def path({_kind, %Order{id: id}}), do: "/admin/orders/#{id}"
  def path({_kind, %Subscription{id: id}}), do: "/admin/subscriptions/#{id}"
  def path({_kind, %CourseRegistration{id: id, course_id: course_id}}), do: "/admin/courses/#{course_id}?booking=#{id}"

  # A retried push replaces its notification rather than adding one, and so
  # does an order's reminder, since by then its new-order notice is old news.
  def tag({_kind, %Order{id: id}}), do: "order-#{id}"
  def tag({_kind, %Subscription{id: id}}), do: "subscription-#{id}"
  def tag({_kind, %CourseRegistration{id: id}}), do: "booking-#{id}"
end
