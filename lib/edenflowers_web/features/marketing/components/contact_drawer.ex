defmodule EdenflowersWeb.Marketing.ContactDrawer do
  @moduledoc """
  Right-hand drawer with a contact form that sends Jennie a message. Render it
  once per page with `id="contact-drawer"` and open it with `open/0`.
  """

  use EdenflowersWeb, :live_component

  alias Edenflowers.ContactMessage

  def open, do: JS.exec("phx-show", to: "#contact-drawer")

  @impl true
  def mount(socket) do
    {:ok, assign(socket, form: build_form(%{}), sent?: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.drawer
        id={@id}
        placement="right"
        label={~t"Send me a message"}
        class="bg-base-100 w-[92vw] h-full overflow-y-auto overscroll-contain sm:w-[34rem]"
      >
        <header class="flex flex-row items-center justify-between gap-4 pt-6 pr-4 pl-4 sm:pt-8 sm:pl-8">
          <h2 class="section-title">{if @sent?, do: ~t"Thank you", else: ~t"Send me a message"}</h2>
          <.icon_button aria_label={~t"Close"} phx-click={JS.exec("phx-hide", to: "##{@id}")}>
            <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
          </.icon_button>
        </header>
        <div class="flex flex-col gap-6 p-4 sm:p-8">
          <p :if={!@sent?} class="text-base-content/80 leading-relaxed">
            {~t"During opening hours I usually reply within 4 hours."}
          </p>
          <.form
            :if={!@sent?}
            for={@form}
            id="contact-form"
            phx-target={@myself}
            phx-change="validate"
            phx-submit="send"
            class="flex flex-col gap-4"
          >
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@form[:name]} label={~t"Your name *"} autocomplete="name" aria-required="true" />
              <.input field={@form[:email]} type="email" label={~t"Email *"} autocomplete="email" aria-required="true" />
            </div>
            <.input field={@form[:phone]} type="tel" label={~t"Phone"} autocomplete="tel" />
            <.input field={@form[:message]} type="textarea" label={~t"Message *"} rows="6" aria-required="true" />
            <%!-- Honeypot: hidden from people, so only bots fill it in. --%>
            <.input field={@form[:website]} hidden tabindex="-1" autocomplete="off" aria-hidden="true" />

            <.button type="submit" variant="primary">{~t"Send message"}</.button>
            <p class="text-base-content/70 text-sm">
              {~t"Or email me directly at"}
              <a href="mailto:info@edenflowers.fi" class="link-underline-static-body">info@edenflowers.fi</a>
            </p>
          </.form>
          <p :if={@sent?} id="contact-sent" class="text-base-content/80">
            {~t"Your message is on its way, and a copy is in your inbox. I'll get back to you as soon as I can."}
          </p>
        </div>
      </.drawer>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    {:noreply, assign(socket, form: build_form(params, :validate))}
  end

  def handle_event("send", %{"message" => params}, socket) do
    case ContactMessage.submit(params, to_string(Edenflowers.Format.locale())) do
      :ok ->
        {:noreply, assign(socket, sent?: true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :message))}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, ~t"Your message couldn't be sent. Please try again, or email me directly.")}
    end
  end

  defp build_form(params, action \\ nil) do
    params
    |> ContactMessage.changeset()
    |> Map.put(:action, action)
    |> to_form(as: :message)
  end
end
