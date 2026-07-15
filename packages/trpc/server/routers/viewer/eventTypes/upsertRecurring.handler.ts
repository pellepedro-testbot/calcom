import type { PrismaClient } from "@calcom/prisma";
import { Prisma } from "@calcom/prisma/client";

import type { TrpcSessionUser } from "../../../types";
import type { TUpsertRecurringConfigSchema } from "./getRecurring.schema";

type UpsertRecurringOptions = {
  ctx: {
    user: NonNullable<TrpcSessionUser>;
    prisma: PrismaClient;
  };
  input: TUpsertRecurringConfigSchema;
};

/**
 * Create or update recurring event configuration on an event type.
 *
 * Cal.com stores recurring settings as a JSON blob in EventType.recurringEvent.
 * This handler merges the incoming config with the RFC 5545 RRULE fields that
 * the booking engine expects.
 */
export const upsertRecurringHandler = async ({
  ctx,
  input,
}: UpsertRecurringOptions): Promise<{ eventTypeId: number; updated: boolean }> => {
  const { eventTypeId, frequency, count, interval, endDate } = input;

  // Ensure the user owns (or is a team member of) this event type
  const eventType = await ctx.prisma.eventType.findFirst({
    where: {
      id: eventTypeId,
      OR: [
        { userId: ctx.user.id },
        {
          team: {
            members: {
              some: { userId: ctx.user.id, role: { in: ["ADMIN", "OWNER"] } },
            },
          },
        },
      ],
    },
    select: { id: true, recurringEvent: true },
  });

  if (!eventType) {
    throw new Error(
      `Event type ${eventTypeId} not found or insufficient permissions`
    );
  }

  const recurringEvent: Record<string, unknown> = {
    freq: frequency,
    count: count ?? 0,
    interval: interval ?? 1,
    ...(endDate ? { until: endDate } : {}),
  };

  await ctx.prisma.eventType.update({
    where: { id: eventTypeId },
    data: {
      recurringEvent: recurringEvent as Prisma.InputJsonValue,
    },
  });

  return { eventTypeId, updated: true };
};
