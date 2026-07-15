import type { PrismaClient } from "@calcom/prisma";

import type { TrpcSessionUser } from "../../../types";
import type { TGetRecurringInputSchema } from "./getRecurring.schema";

type GetRecurringOptions = {
  ctx: {
    user: NonNullable<TrpcSessionUser>;
    prisma: PrismaClient;
  };
  input: TGetRecurringInputSchema;
};

export type RecurringConfig = {
  id: number;
  eventTypeId: number;
  frequency: "DAILY" | "WEEKLY" | "MONTHLY" | "YEARLY";
  count: number;
  interval: number;
  endDate: string | null;
};

/**
 * Retrieve the recurring event configuration for a given event type.
 * Returns null if the event type has no recurring configuration.
 */
export const getRecurringHandler = async ({
  ctx,
  input,
}: GetRecurringOptions): Promise<RecurringConfig | null> => {
  const { eventTypeId } = input;

  // Verify the event type belongs to the requesting user (or their team)
  const eventType = await ctx.prisma.eventType.findFirst({
    where: {
      id: eventTypeId,
      OR: [
        { userId: ctx.user.id },
        { team: { members: { some: { userId: ctx.user.id } } } },
      ],
    },
    select: {
      id: true,
      recurringEvent: true,
    },
  });

  if (!eventType) {
    throw new Error(
      `Event type ${eventTypeId} not found or not accessible by user ${ctx.user.id}`
    );
  }

  const recurringEvent = eventType.recurringEvent as Record<string, unknown> | null;

  if (!recurringEvent) {
    return null;
  }

  return {
    id: eventTypeId,
    eventTypeId,
    frequency: (recurringEvent.freq as RecurringConfig["frequency"]) ?? "WEEKLY",
    count: (recurringEvent.count as number) ?? 0,
    interval: (recurringEvent.interval as number) ?? 1,
    endDate: (recurringEvent.until as string) ?? null,
  };
};
