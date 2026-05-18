defmodule EdenflowersWeb.CheckoutComponents do
  use EdenflowersWeb, :html

  alias Edenflowers.Store.Order

  @checkout_states Order.checkout_states()

  attr :state, :atom, required: true
  attr :order, :map, required: true
  slot :inner_block

  def steps(assigns) do
    assigns = assign(assigns, :states, @checkout_states)

    ~H"""
    <ol class="flex flex-col">
      <.checkout_step
        :for={state <- @states}
        state={state}
        current_state={@state}
        order={@order}
      >
        <%= if state == @state do %>
          {render_slot(@inner_block)}
        <% end %>
      </.checkout_step>
    </ol>
    """
  end

  attr :state, :atom, required: true
  attr :current_state, :atom, required: true
  attr :order, :map, required: true
  slot :inner_block

  defp checkout_step(assigns) do
    past? = state_index(assigns.state) < state_index(assigns.current_state)
    current? = assigns.state == assigns.current_state
    future? = not past? and not current?

    assigns =
      assigns
      |> assign(:past?, past?)
      |> assign(:current?, current?)
      |> assign(:future?, future?)
      |> assign(:position_label, position_label(assigns.state))
      |> assign(:title, step_title(assigns.state))
      |> assign(:summary, past? && step_summary(assigns.state, assigns.order))
      |> assign(:a11y_status, a11y_status(past?, current?))

    ~H"""
    <li class={["border-base-content/12 py-8 md:py-10", not first_step?(@state) && "border-t"]}>
      <div class="flex items-baseline justify-between gap-4">
        <div class="flex items-baseline gap-3">
          <span aria-hidden="true" class={position_classes(@current?)}>
            {@position_label}
          </span>
          <h2 class={title_classes(@past?, @future?)}>
            <span class="sr-only">{@a11y_status}: </span>
            <span>{@title}</span>
            <.icon
              :if={@past?}
              name="hero-check-mini"
              class="size-4 text-base-content/70 self-center"
            />
          </h2>
        </div>
        <.link
          :if={@past?}
          phx-click={JS.push("edit_step", value: %{state: @state})}
          class="link-underline-hover-nav shrink-0 text-sm"
        >
          {~t"Edit"}
        </.link>
      </div>

      <p :if={@past? and @summary} class="text-base-content/70 mt-3">
        {@summary}
      </p>

      <%!-- Active-step content. steps/1 only passes inner_block to the matching row,
           and this guard makes the contract visible in the leaf component too. --%>
      <div :if={@current?} class="mt-8">
        {render_slot(@inner_block)}
      </div>
    </li>
    """
  end

  defp state_index(state), do: Enum.find_index(@checkout_states, &(&1 == state))

  defp first_step?(state), do: state_index(state) == 0

  defp position_label(state) do
    state
    |> state_index()
    |> Kernel.+(1)
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end

  defp position_classes(true), do: ["eyebrow tabular-nums", "text-[var(--color-link-underline)]"]
  defp position_classes(false), do: ["eyebrow tabular-nums", "text-base-content/55"]

  defp title_classes(past?, future?) do
    base = "section-title flex items-baseline gap-2"

    cond do
      past? -> [base, "text-base-content/70"]
      future? -> [base, "text-base-content/40"]
      # :current uses the default text color — no class needed.
      true -> [base]
    end
  end

  defp a11y_status(true, _), do: ~t"Completed"
  defp a11y_status(_, true), do: ~t"Current step"
  defp a11y_status(_, _), do: ~t"Upcoming"

  defp step_title(:contact_details), do: ~t"Your details"
  defp step_title(:gift_options), do: ~t"Gift options"
  defp step_title(:delivery), do: ~t"Delivery"
  defp step_title(:payment), do: ~t"Payment"

  defp step_summary(:contact_details, %{customer_name: name, customer_email: email})
       when is_binary(name) and is_binary(email),
       do: "#{name} · #{email}"

  defp step_summary(:gift_options, %{gift: false}), do: ~t"For me"
  defp step_summary(:gift_options, %{gift: true, recipient_name: name}) when is_binary(name), do: ~t"For #{name}"
  defp step_summary(:gift_options, _), do: nil

  defp step_summary(:delivery, %{fulfillment_method: method, fulfillment_date: date} = order)
       when not is_nil(method) and not is_nil(date) do
    method_label = if method == :delivery, do: ~t"Home delivery", else: ~t"In-store pickup"
    address = if method == :delivery, do: order.delivery_address, else: nil

    [method_label, format_date(date), address]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp step_summary(_, _), do: nil

  defp format_date(%Date{} = date) do
    locale = Localize.get_locale().cldr_locale_id
    Localize.Date.to_string!(date, locale: locale, format: :medium)
  end

  defp format_date(_), do: nil
end
