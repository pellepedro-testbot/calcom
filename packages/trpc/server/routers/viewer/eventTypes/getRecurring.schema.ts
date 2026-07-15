import { z } from "zod";

export const recurringFrequencySchema = z.enum([
  "DAILY",
  "WEEKLY",
  "MONTHLY",
  "YEARLY",
]);

export type RecurringFrequency = z.infer<typeof recurringFrequencySchema>;

export const ZGetRecurringInputSchema = z.object({
  eventTypeId: z.number().int().positive(),
});

export type TGetRecurringInputSchema = z.infer<typeof ZGetRecurringInputSchema>;

export const ZUpsertRecurringConfigSchema = z.object({
  eventTypeId: z.number().int().positive(),
  frequency: recurringFrequencySchema,
  /** How many occurrences to create at most. 0 means unlimited. */
  count: z.number().int().min(0).max(365).default(0),
  /** Interval between recurrences, e.g. every 2 weeks. */
  interval: z.number().int().min(1).max(52).default(1),
  /** ISO date string for when the recurrence should stop (optional). */
  endDate: z.string().datetime().nullable().optional(),
});

export type TUpsertRecurringConfigSchema = z.infer<
  typeof ZUpsertRecurringConfigSchema
>;
