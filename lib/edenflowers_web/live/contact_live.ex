defmodule EdenflowersWeb.ContactLive do
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-16 md:mb-20">{~t"Contact"}</h1>

        <div class="max-w-3xl space-y-12">
          <p class="text-base-content/80 text-lg">
            {~t"Got a question, a special request, or want to talk through an arrangement? Reach us by email or phone, or stop by the shop during opening hours."}
          </p>

          <dl class="grid grid-cols-1 gap-10 sm:grid-cols-2">
            <div class="space-y-2">
              <dt class="eyebrow text-base-content/60">{~t"Email"}</dt>
              <dd>
                <a class="footer-line link-underline-hover-nav" href="mailto:info@edenflowers.fi">
                  info@edenflowers.fi
                </a>
              </dd>
            </div>

            <div class="space-y-2">
              <dt class="eyebrow text-base-content/60">{~t"Phone"}</dt>
              <dd>
                <a class="footer-line link-underline-hover-nav" href="tel:+358402209494">
                  040 220 9494
                </a>
              </dd>
            </div>

            <div class="space-y-2">
              <dt class="eyebrow text-base-content/60">{~t"Address"}</dt>
              <dd class="not-italic">
                <address class="space-y-1 not-italic">
                  <p class="footer-line">Minimossen</p>
                  <p class="footer-line">{~t"Myrvägen 1"}</p>
                  <p class="footer-line">{~t"65230 Vasa"}</p>
                </address>
              </dd>
            </div>

            <div class="space-y-2">
              <dt class="eyebrow text-base-content/60">{~t"Opening hours"}</dt>
              <dd>
                <ul class="space-y-1">
                  <li class="footer-line">{~t"Mon–Fri: 09:00–17:00"}</li>
                  <li class="footer-line">{~t"Sat: 10:00–15:00"}</li>
                  <li class="footer-line">{~t"Sun: closed"}</li>
                </ul>
              </dd>
            </div>
          </dl>
        </div>
      </.container>
    </Layouts.app>
    """
  end
end
