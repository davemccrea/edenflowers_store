defmodule Edenflowers.Courses.CourseTest do
  use Edenflowers.DataCase, async: true

  import Generator

  for {season, date, utc_end} <- [
        {:winter, ~D[2026-01-15], ~U[2026-01-15 11:00:00Z]},
        {:summer, ~D[2026-07-15], ~U[2026-07-15 10:00:00Z]},
        {:midnight, ~D[2026-07-15], ~U[2026-07-14 21:30:00Z]}
      ] do
    @tag date: date, utc_end: utc_end, end_time: if(season == :midnight, do: ~T[00:30:00], else: ~T[13:00:00])
    test "course ends at its exact Helsinki end time in #{season}", ctx do
      course = generate(course(date: ctx.date, end_time: ctx.end_time))

      before_end = Ash.load!(course, [ended?: [now: DateTime.add(ctx.utc_end, -1, :second)]], authorize?: false)
      at_end = Ash.load!(course, [ended?: [now: ctx.utc_end]], authorize?: false)
      after_end = Ash.load!(course, [ended?: [now: DateTime.add(ctx.utc_end, 1, :second)]], authorize?: false)

      refute before_end.ended?
      assert at_end.ended?
      assert after_end.ended?
    end
  end
end
