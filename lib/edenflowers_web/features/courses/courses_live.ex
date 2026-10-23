defmodule EdenflowersWeb.Courses.CoursesLive do
  @moduledoc """
  Public list of upcoming florist courses.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Translations
  alias EdenflowersWeb.Business

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, socket) do
    courses =
      [load: [:seats_left, :booking_open?], query: [sort: [date: :asc, start_time: :asc]]]
      |> Courses.list_upcoming_courses!()
      |> Translations.translate()

    {:ok,
     assign(socket,
       page_title: ~t"Floristry Courses in Vaasa",
       alternates: alternates("/#{language}/courses"),
       page_description:
         ~t"Floristry courses with Jennie at Eden Flowers in Vaasa. See upcoming dates and book your seat.",
       locale: Format.locale(),
       courses: courses
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      alternates={@alternates}
    >
      <.container>
        <section class="flex flex-col gap-12 md:flex-row md:items-center md:gap-16 lg:gap-24">
          <div class="flex max-w-2xl flex-col gap-6">
            <h1 class="page-title mb-4">{~t"Courses"}</h1>
            <p class="text-base-content/80 text-lg leading-relaxed">
              {~t"Come along and learn to make different kinds of floral arrangements. I show you the technique step by step and help you all the way, and of course you take your arrangement home. Materials and teaching are included, and you don't need any previous experience."}
            </p>
            <div class="mt-2">
              <.button href="#coming-up" variant="primary">{~t"See upcoming courses"}</.button>
            </div>
          </div>
          <%!-- Hidden on phones so the dates, which are what people came for, sit above the fold. --%>
          <div class="hidden flex-shrink-0 md:block md:w-80 lg:w-96">
            <.image
              src="local:///jennie_4.jpg"
              alt=""
              width={800}
              height={1200}
              sizes="(min-width: 1024px) 24rem, 20rem"
              class="aspect-[2/3] w-full object-cover"
            />
          </div>
        </section>

        <section
          id="coming-up"
          class="border-base-content/12 scroll-anchor-below-header mt-14 border-t pt-10 sm:mt-20 sm:pt-14"
          aria-labelledby="upcoming-heading"
        >
          <div class="max-w-2xl">
            <h2 id="upcoming-heading" class="section-title">{~t"Coming up"}</h2>

            <div :if={@courses == []} class="mt-6" data-testid="no-courses">
              <p class="text-base-content/80 max-w-prose">
                {~t"There are no courses on the calendar right now. I announce new dates in the newsletter first."}
              </p>
              <.button href="#newsletter" variant="text" class="mt-4">{~t"Sign up for the newsletter"}</.button>
            </div>

            <ol :if={@courses != []} class="mt-8" data-testid="courses-list">
              <li :for={course <- @courses} class="border-base-content/12 border-t first:border-t-0">
                <.course_row course={course} locale={@locale} />
              </li>
            </ol>
          </div>
        </section>

        <section
          id="groups"
          class="bg-cream text-cream-content scroll-anchor-below-header mt-16 grid sm:mt-24 md:grid-cols-[2fr_3fr]"
          aria-labelledby="groups-heading"
        >
          <.image
            src="local:///image_5.jpg"
            alt=""
            width={1500}
            height={1000}
            sizes="(min-width: 768px) 40vw, 100vw"
            class="aspect-[4/3] object-[69%_30%] h-full w-full object-cover md:aspect-auto"
          />

          <div class="flex flex-col items-start gap-6 px-6 py-12 sm:px-10 md:justify-center md:px-12 md:py-16 lg:px-16 lg:py-20">
            <.flower name="flower-30" class="text-cream-content/60 h-12 w-12" />
            <h2 id="groups-heading" class="section-title text-balance">{~t"A course for your group"}</h2>
            <p class="max-w-prose text-lg leading-relaxed">
              {~t"I also run private courses, for example at a Christmas party, a staff wellbeing day or a hen party. We can meet in the shop in Minimossen or at your place, and in summer we're happy to make flower crowns in a park. Bouquet courses take up to 15 people, because I help each of you with your hands. Wreath courses take up to 30."}
            </p>
            <p class="max-w-prose">{~t"Email or call me, and we'll find a day."}</p>
            <div class="flex flex-wrap items-center gap-x-6 gap-y-3">
              <.button href={"mailto:#{Business.email()}"} variant="primary">{Business.email()}</.button>
              <a href={"tel:#{Business.phone()}"} class="link-underline-static-body whitespace-nowrap">
                {Business.phone_display()}
              </a>
            </div>
          </div>
        </section>
      </.container>
    </Layouts.app>
    """
  end

  attr :course, :map, required: true
  attr :locale, :any, required: true

  # A full or closed course keeps its row: it still tells people courses happen.
  defp course_row(assigns) do
    ~H"""
    <div class="grid-cols-[5rem_1fr] relative grid items-baseline gap-x-4 gap-y-2 py-6 sm:grid-cols-[8rem_1fr_auto] sm:gap-x-8">
      <p class="text-base-content/70 tabular-nums">{Format.day_month(@course.date, @locale)}</p>

      <div>
        <h3 class="card-heading text-balance">
          <%!-- The link's ::after covers the whole row, so the date and price click through too. --%>
          <.link
            :if={@course.booking_open?}
            navigate={~q"/#{language}/courses/#{@course.id}"}
            class="link-underline-hover after:content-[''] after:absolute after:-inset-x-3 after:inset-y-0 focus-visible:outline-hidden focus-visible:after:border-primary focus-visible:after:border-2"
          >
            {@course.name}
          </.link>
          <span :if={!@course.booking_open?} class="text-base-content/70">{@course.name}</span>
        </h3>
        <p class="text-base-content/70 mt-1 text-sm tabular-nums">
          {Format.time(@course.start_time, @locale)}–{Format.time(@course.end_time, @locale)} · {@course.location_name} ·
          <span data-testid="course-language">{taught_in(@course.language)}</span>
        </p>
      </div>

      <div class="col-start-2 sm:col-start-3 sm:row-start-1 sm:text-right">
        <p class="text-base-content font-serif text-xl tabular-nums">{Format.storefront_price(@course.price, @locale)}</p>
        <p class="text-base-content/70 text-sm">{availability(@course)}</p>
      </div>
    </div>
    """
  end

  defp taught_in(:sv), do: ~t"In Swedish"
  defp taught_in(:fi), do: ~t"In Finnish"
  defp taught_in(:en), do: ~t"In English"

  defp availability(%{seats_left: seats_left}) when seats_left <= 0, do: ~t"Fully booked"
  defp availability(%{booking_open?: false}), do: ~t"Booking closed"
  defp availability(%{seats_left: seats_left}), do: ~t"#{count = seats_left} place(s) left"N
end
