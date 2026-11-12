defmodule Edenflowers.Orders.Order.Changes.SendFulfillmentEmail do
  @moduledoc """
  Emails a customer when their order is delivered: Left at the door, with
  its photo, when nobody was home, else Delivered. A successful send stamps `fulfillment_emailed_at` and clears
  `fulfillment_email_failed_at`. A failed send fails the action, so the AshOban
  trigger retries it and, once attempts run out, `record_fulfillment_email_failure`
  stamps `fulfillment_email_failed_at` for the admin to see.
  """

  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &send_email/1)
  end

  defp send_email(changeset) do
    order = Ash.load!(changeset.data, load(), authorize?: false)
    edits = Edits.from_changeset(changeset)

    case photo(order) do
      {:ok, photo} ->
        {kind, email} = email(order, order.email_delivery_photo, photo)

        changeset
        |> Ash.Changeset.set_context(%{paper_trail_metadata: Map.put(Edits.for_log(edits), :fulfillment_email, kind)})
        |> deliver(order, Edits.apply_to(email, edits))

      {:error, error} ->
        Ash.Changeset.add_error(changeset, field: :delivery_photo_slug, message: email_error(error))
    end
  end

  defp deliver(changeset, order, email) do
    case Mailer.deliver(email) do
      {:ok, _result} ->
        Logger.info("Sent fulfillment email for order #{order.id}")

        changeset
        |> Ash.Changeset.force_change_attributes(
          fulfillment_emailed_at: DateTime.utc_now(),
          fulfillment_emailed_to: order.customer_email
        )
        |> clear_failure()

      {:error, error} ->
        Ash.Changeset.add_error(changeset, email_error(error))
    end
  end

  defp email_error(error), do: ~t"Failed to send fulfillment email: #{error = inspect(error)}"

  @doc "What the order is loaded with to build its email."
  def load, do: [:customer_first_name]

  @doc """
  The email for an order loaded with `load/0`, and its name for the log:
  Left at the door with `photo` attached when `photo?`, else Delivered.
  """
  def email(order, true, photo), do: {"left_at_door", Email.order_left_at_door(order, photo)}
  def email(order, _photo?, _photo), do: {"delivered", Email.order_delivered(order)}

  defp photo(%{email_delivery_photo: true, delivery_photo_slug: slug}) when is_binary(slug) and byte_size(slug) > 0,
    do: fetch_small_photo(slug)

  defp photo(%{email_delivery_photo: true}), do: {:error, ~t"Delivery photo is missing."}
  defp photo(_order), do: {:ok, nil}

  # A phone photo can be 10 MB or more. 1600 px at quality 80 comes to a few
  # hundred KB: small enough for any inbox, sharp enough to spot a doorstep.
  defp fetch_small_photo(slug) do
    url =
      slug
      |> Imgproxy.new()
      |> Imgproxy.resize(1600, 1600, type: "fit")
      |> Imgproxy.add_option(:q, [80])
      |> Imgproxy.set_extension("jpg")
      |> to_string()

    case Req.get(url, Application.get_env(:edenflowers, :delivery_photo_req_options, [])) do
      {:ok, %{status: 200, body: jpeg}} -> {:ok, jpeg}
      {:ok, %{status: status}} -> {:error, "imgproxy answered #{status} for the delivery photo"}
      {:error, error} -> {:error, error}
    end
  end

  # Clear the failure in the database even if the caller's stale record already has a nil timestamp.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :fulfillment_email_failed_at, nil)
end
