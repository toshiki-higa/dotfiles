/**
 * Tool Input Repair Extension for pi
 *
 * Automatically repairs structurally invalid tool-call arguments produced by
 * LLMs before pi's schema validation rejects them. Inspired by the schema-driven
 * repair catalogue introduced in Command Code v1 (1.0.0–1.4.6), adapted for pi's
 * built-in tools and safety requirements.
 *
 * Supported tools: read, bash, edit, write, grep, find, ls
 *
 * Repair catalogue (applied per field, in order):
 *   1.  dropNullOrUndefinedField   — remove null/undefined values
 *   2.  dropEmptyObjectPlaceholder  — remove {} on non-object fields
 *   3.  coerceStringToNumber       — "10" → 10
 *   4.  coerceStringToBoolean      — "true" → true
 *   5.  parseJsonStringifiedArray  — "[{…}]" → [{…}]
 *   6.  parseJsonStringifiedObject — "{…}" → {…}
 *   7.  wrapBareScalarAsArray      — value → [value]
 *   8.  stripMarkdownLinkFromPath  — [label](path) → path
 *   9.  renameAliasedField         — file_path → path, etc.
 *   10. dropUnknownKey             — remove fields not in schema
 *
 * Root coercion:
 *   - Single-object array unwrapped: [{ … }] → { … }
 *   - JSON-stringified object parsed: "{…}" → {…}
 *   - Bare string wrapped only when schema has exactly one required string
 *
 * Recursive repair:
 *   - Object array items (e.g. edit.edits[]) are repaired recursively,
 *     including alias renaming (old_string → oldText) and unknown field
 *     removal within each item.
 *
 * Intentional differences from Command Code v1:
 *   - Conflicting aliases (same canonical, different values) are dropped,
 *     not first-wins. Ambiguity is left to pi validation.
 *   - Root-level old_string/new_string are NOT synthesized into edits[].
 *     Alias repair only applies at schema-known nesting levels.
 *   - timeout_ms/timeoutMs are NOT aliased to timeout (pi uses seconds,
 *     Command Code used milliseconds).
 *   - No custom validation error messages; pi's standard schema validation
 *     handles post-repair errors.
 *   - No repair telemetry.
 *
 * References:
 *   - Command Code: command-code@1.0.0 (catalogue introduced), 1.4.6 (latest
 *     checked, catalogue unchanged from 1.0.0)
 *   - pi: @earendil-works/pi-coding-agent 0.82.1
 */

import {
  createBashToolDefinition,
  createEditToolDefinition,
  createFindToolDefinition,
  createGrepToolDefinition,
  createLsToolDefinition,
  createReadToolDefinition,
  createWriteToolDefinition,
  type ExtensionAPI,
} from '@earendil-works/pi-coding-agent';

type BuiltinToolName = 'read' | 'bash' | 'edit' | 'write' | 'grep' | 'find' | 'ls';
type Input = Record<string, unknown>;

export type RepairSchema =
  | {
      readonly type: 'object';
      readonly properties: Readonly<Record<string, RepairSchema>>;
      readonly required: ReadonlySet<string>;
    }
  | {
      readonly type: 'array';
      readonly items: RepairSchema;
    }
  | {
      readonly type: 'string' | 'number' | 'boolean';
    };

interface RepairableDefinition {
  name: string;
  parameters: unknown;
  prepareArguments?: (input: unknown) => unknown;
}

export interface RepairToolInputOptions {
  toolName: BuiltinToolName;
  schema: RepairSchema;
  rawInput: unknown;
  repairNotes?: string[];
}

const BUILTIN_TOOL_NAMES = new Set<BuiltinToolName>([
  'read',
  'bash',
  'edit',
  'write',
  'grep',
  'find',
  'ls',
]);

const isBuiltinToolName = (name: string): name is BuiltinToolName =>
  BUILTIN_TOOL_NAMES.has(name as BuiltinToolName);

const FIELD_ALIASES: Record<BuiltinToolName, Readonly<Record<string, readonly string[]>>> = {
  read: {
    path: [
      'absolutePath',
      'file_path',
      'filePath',
      'filepath',
      'pathname',
      'target_file',
      'targetFile',
      'file',
      'absolute_path',
      'fileAbsolutePath',
    ],
  },
  bash: {
    command: ['cmd', 'bash', 'shell', 'script', 'commandLine'],
  },
  edit: {
    path: [
      'filePath',
      'absolutePath',
      'absolute_path',
      'file_path',
      'filepath',
      'pathname',
      'target_file',
      'targetFile',
      'fileName',
      'file_name',
      'filename',
    ],
    oldText: [
      'old_string',
      'oldString',
      'oldValue',
      'old',
      'old_str',
      'oldStr',
      'from',
      'old_value',
      'old_text',
      'oldContent',
      'old_content',
    ],
    newText: [
      'new_string',
      'newString',
      'newValue',
      'new',
      'new_str',
      'newStr',
      'to',
      'new_value',
      'new_text',
      'newContent',
      'new_content',
    ],
  },
  write: {
    path: [
      'filePath',
      'absolutePath',
      'absolute_path',
      'file_path',
      'filepath',
      'pathname',
      'target_file',
      'targetFile',
      'fileName',
      'file_name',
      'filename',
    ],
    content: ['text', 'body', 'data', 'contents', 'fileContent'],
  },
  grep: {
    pattern: ['query', 'regex', 'search', 'q', 'expression', 'text'],
    path: ['directory', 'dir', 'folder', 'searchPath', 'search_path'],
  },
  find: {
    pattern: ['query', 'glob', 'expression', 'search', 'include'],
    path: ['directory', 'dir', 'folder', 'searchPath', 'search_path'],
  },
  ls: {
    path: ['absolutePath', 'directory', 'dir', 'folder', 'directoryPath'],
  },
};

const createAliasLookup = (
  aliases: Readonly<Record<string, readonly string[]>>,
): Readonly<Record<string, string>> => {
  const lookup: Record<string, string> = Object.create(null);
  for (const [canonical, candidates] of Object.entries(aliases)) {
    for (const candidate of candidates) lookup[candidate] = canonical;
  }
  return lookup;
};

const FIELD_ALIAS_LOOKUPS: Record<BuiltinToolName, Readonly<Record<string, string>>> = {
  read: createAliasLookup(FIELD_ALIASES.read),
  bash: createAliasLookup(FIELD_ALIASES.bash),
  edit: createAliasLookup(FIELD_ALIASES.edit),
  write: createAliasLookup(FIELD_ALIASES.write),
  grep: createAliasLookup(FIELD_ALIASES.grep),
  find: createAliasLookup(FIELD_ALIASES.find),
  ls: createAliasLookup(FIELD_ALIASES.ls),
};

const LOG_REPAIRS = process.env.PI_LOG_TOOL_REPAIRS === '1';

const isInput = (value: unknown): value is Input =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const normalizeSchemaProperties = (
  value: unknown,
): Readonly<Record<string, RepairSchema>> | undefined => {
  if (!isInput(value)) return undefined;

  const properties: Record<string, RepairSchema> = Object.create(null);
  for (const [key, rawProperty] of Object.entries(value)) {
    const property = normalizeRepairSchema(rawProperty);
    if (!property) return undefined;
    properties[key] = property;
  }
  return properties;
};

export const normalizeRepairSchema = (rawSchema: unknown): RepairSchema | undefined => {
  if (!isInput(rawSchema)) return undefined;

  switch (rawSchema.type) {
    case 'string':
    case 'number':
    case 'boolean':
      return { type: rawSchema.type };

    case 'array': {
      const items = normalizeRepairSchema(rawSchema.items);
      return items ? { type: 'array', items } : undefined;
    }

    case 'object': {
      const properties = normalizeSchemaProperties(rawSchema.properties);
      if (!properties) return undefined;

      const required = rawSchema.required;
      if (
        required !== undefined &&
        (!Array.isArray(required) || required.some((field) => typeof field !== 'string'))
      ) {
        return undefined;
      }

      const requiredFields = new Set<string>((required as string[] | undefined) ?? []);
      for (const field of requiredFields) {
        if (!Object.hasOwn(properties, field)) return undefined;
      }

      return { type: 'object', properties, required: requiredFields };
    }

    default:
      return undefined;
  }
};

const sameValue = (left: unknown, right: unknown): boolean => {
  if (Object.is(left, right)) return true;
  if (typeof left !== typeof right || left === null || right === null) return false;
  if (typeof left !== 'object') return false;
  return JSON.stringify(left) === JSON.stringify(right);
};

/** Non-null, non-undefined, and not an empty string. */
const isUsableValue = (value: unknown): boolean =>
  value !== null && value !== undefined && (typeof value !== 'string' || value.length > 0);

const hasCanonicalValue = (input: Input, field: string): boolean =>
  Object.hasOwn(input, field) && isUsableValue(input[field]);

const getConflictingAliasFields = (
  input: Input,
  aliasLookup: Readonly<Record<string, string>>,
): ReadonlySet<string> => {
  const candidates = new Map<string, unknown>();
  const conflicts = new Set<string>();

  for (const [alias, value] of Object.entries(input)) {
    const canonical = aliasLookup[alias];
    if (!canonical || hasCanonicalValue(input, canonical) || !isUsableValue(value)) continue;

    if (!candidates.has(canonical)) {
      candidates.set(canonical, value);
    } else if (!sameValue(candidates.get(canonical), value)) {
      conflicts.add(canonical);
    }
  }

  return conflicts;
};

const markdownLinkTarget = (value: string): string | undefined => {
  const match = /^\[[^\]\n]*\]\(([^)\n]+)\)$/.exec(value.trim());
  return match?.[1];
};

interface RootCoercion {
  value: unknown;
  changed: boolean;
}

const coerceRootInput = (
  schema: RepairSchema,
  rawInput: unknown,
  repairNotes?: string[],
): RootCoercion => {
  if (Array.isArray(rawInput) && rawInput.length === 1 && isInput(rawInput[0])) {
    repairNotes?.push('unwrapped a single-object root array');
    return { value: rawInput[0], changed: true };
  }

  if (typeof rawInput !== 'string') {
    return { value: rawInput, changed: false };
  }

  const trimmed = rawInput.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    try {
      const parsed: unknown = JSON.parse(trimmed);
      if (isInput(parsed)) {
        repairNotes?.push('parsed a JSON-stringified root object');
        return { value: parsed, changed: true };
      }
    } catch {
      // Leave malformed JSON untouched so pi reports the validation error.
    }
  }

  if (schema.type !== 'object' || schema.required.size !== 1) {
    return { value: rawInput, changed: false };
  }

  const [field] = schema.required;
  if (!field || schema.properties[field]?.type !== 'string') {
    return { value: rawInput, changed: false };
  }

  repairNotes?.push(`wrapped root string as ${field}`);
  return { value: { [field]: rawInput }, changed: true };
};

const parseJsonArray = (value: string): unknown[] | undefined => {
  if (!value.trim().startsWith('[')) return undefined;
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
};

const parseJsonObject = (value: string): Input | undefined => {
  if (!value.trim().startsWith('{')) return undefined;
  try {
    const parsed: unknown = JSON.parse(value);
    return isInput(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
};

const repairAlias = (
  input: Input,
  alias: string,
  schema: Extract<RepairSchema, { type: 'object' }>,
  aliasLookup: Readonly<Record<string, string>>,
  conflictingAliases: ReadonlySet<string>,
  path: string,
  repairNotes?: string[],
): boolean => {
  const canonical = aliasLookup[alias];
  if (
    !canonical ||
    !Object.hasOwn(schema.properties, canonical) ||
    conflictingAliases.has(canonical) ||
    hasCanonicalValue(input, canonical) ||
    !isUsableValue(input[alias])
  ) {
    return false;
  }

  const matchingAliases = Object.keys(input).filter(
    (field) => aliasLookup[field] === canonical && isUsableValue(input[field]),
  );
  if (matchingAliases.length === 0) return false;

  input[canonical] = input[matchingAliases[0]!];
  for (const field of matchingAliases) delete input[field];
  repairNotes?.push(`renamed ${path}${matchingAliases.join('/')} to ${path}${canonical}`);
  return true;
};

interface RepairObjectOptions {
  toolName: BuiltinToolName;
  schema: Extract<RepairSchema, { type: 'object' }>;
  input: Input;
  path: string;
  repairNotes?: string[];
}

const repairObject = ({
  toolName,
  schema,
  input,
  path,
  repairNotes,
}: RepairObjectOptions): boolean => {
  const aliasLookup = FIELD_ALIAS_LOOKUPS[toolName];
  const conflictingAliases = getConflictingAliasFields(input, aliasLookup);
  const originalFields = Object.keys(input);
  let changed = false;

  for (const field of originalFields) {
    if (!Object.hasOwn(input, field)) continue;

    const fieldPath = `${path}${field}`;
    const expected = schema.properties[field];
    const value = input[field];

    if (value === null || value === undefined) {
      delete input[field];
      repairNotes?.push(`dropped null/undefined field ${fieldPath}`);
      changed = true;
      continue;
    }

    if (expected?.type !== 'object' && isInput(value) && Object.keys(value).length === 0) {
      delete input[field];
      repairNotes?.push(`dropped empty-object placeholder ${fieldPath}`);
      changed = true;
      continue;
    }

    if (expected?.type === 'number' && typeof value === 'string') {
      const trimmed = value.trim();
      if (trimmed !== '' && !Number.isNaN(Number(trimmed))) {
        input[field] = Number(trimmed);
        repairNotes?.push(`coerced ${fieldPath} string to number`);
        changed = true;
        continue;
      }
    }

    if (
      expected?.type === 'boolean' &&
      typeof value === 'string' &&
      (value === 'true' || value === 'false')
    ) {
      input[field] = value === 'true';
      repairNotes?.push(`coerced ${fieldPath} string to boolean`);
      changed = true;
      continue;
    }

    if (expected?.type === 'array' && typeof value === 'string') {
      const parsed = parseJsonArray(value);
      if (parsed) {
        input[field] = parsed;
        repairNotes?.push(`parsed JSON-stringified array ${fieldPath}`);
        changed = true;
        continue;
      }
    }

    if (expected?.type === 'object' && typeof value === 'string') {
      const parsed = parseJsonObject(value);
      if (parsed) {
        input[field] = parsed;
        repairNotes?.push(`parsed JSON-stringified object ${fieldPath}`);
        changed = true;
        continue;
      }
    }

    if (expected?.type === 'array' && !Array.isArray(value)) {
      input[field] = [value];
      repairNotes?.push(`wrapped scalar ${fieldPath} in a one-element array`);
      changed = true;
      continue;
    }

    if (field === 'path' && expected?.type === 'string' && typeof value === 'string') {
      const target = markdownLinkTarget(value);
      if (target !== undefined) {
        input[field] = target;
        repairNotes?.push(`stripped Markdown link from ${fieldPath}`);
        changed = true;
        continue;
      }
    }

    if (!expected) {
      if (
        repairAlias(
          input,
          field,
          schema,
          aliasLookup,
          conflictingAliases,
          path,
          repairNotes,
        )
      ) {
        changed = true;
        continue;
      }
      delete input[field];
      repairNotes?.push(`dropped unknown field ${fieldPath}`);
      changed = true;
    }
  }

  for (const [field, value] of Object.entries(input)) {
    const expected = schema.properties[field];
    if (expected?.type !== 'array' || expected.items.type !== 'object' || !Array.isArray(value)) {
      continue;
    }

    let repairedItems = value;
    for (let index = 0; index < value.length; index++) {
      const item = value[index];
      if (!isInput(item)) continue;

      const repaired = { ...item };
      const itemChanged = repairObject({
        toolName,
        schema: expected.items,
        input: repaired,
        path: `${path}${field}[${index}].`,
        repairNotes,
      });
      if (!itemChanged) continue;

      if (repairedItems === value) repairedItems = [...value];
      repairedItems[index] = repaired;
      changed = true;
    }

    if (repairedItems !== value) input[field] = repairedItems;
  }

  return changed;
};

export const repairToolInput = ({
  toolName,
  schema,
  rawInput,
  repairNotes,
}: RepairToolInputOptions): unknown => {
  const repairs = repairNotes ?? (LOG_REPAIRS ? [] : undefined);
  const root = coerceRootInput(schema, rawInput, repairs);
  if (schema.type !== 'object' || !isInput(root.value)) return root.value;

  const input = { ...root.value };
  const changed = repairObject({
    toolName,
    schema,
    input,
    path: '',
    repairNotes: repairs,
  });

  if (LOG_REPAIRS && repairs?.length) {
    process.stderr.write(`[tool-repair] ${toolName}: ${repairs.join(', ')}\n`);
  }

  return root.changed || changed ? input : rawInput;
};

const withRepair = <T extends RepairableDefinition>(definition: T, schema: RepairSchema): T => {
  const prepareArguments = definition.prepareArguments;

  return {
    ...definition,
    prepareArguments(input: unknown) {
      const repaired = repairToolInput({
        toolName: definition.name as BuiltinToolName,
        schema,
        rawInput: input,
      });
      return prepareArguments ? prepareArguments(repaired) : repaired;
    },
  } as T;
};

export default function repairToolCalling(pi: ExtensionAPI): void {
  const repairNotesByToolCallId = new Map<string, string[]>();
  const schemasByToolName = new Map<BuiltinToolName, RepairSchema>();

  pi.on('message_end', (event) => {
    if (event.message.role !== 'assistant') return;

    let changed = false;
    const content = event.message.content.map((block) => {
      if (block.type !== 'toolCall' || !isBuiltinToolName(block.name)) return block;

      const schema = schemasByToolName.get(block.name);
      if (!schema) return block;

      const notes: string[] = [];
      const repaired = repairToolInput({
        toolName: block.name,
        schema,
        rawInput: block.arguments,
        repairNotes: notes,
      });
      if (notes.length === 0 || !isInput(repaired)) return block;

      changed = true;
      repairNotesByToolCallId.set(block.id, notes);
      return { ...block, arguments: repaired };
    });

    if (changed) return { message: { ...event.message, content } };
  });

  pi.on('tool_result', (event) => {
    const notes = repairNotesByToolCallId.get(event.toolCallId);
    if (!notes) return;

    repairNotesByToolCallId.delete(event.toolCallId);
    return {
      content: [
        {
          type: 'text' as const,
          text: notes.map((note) => `<repair_note>${note}</repair_note>`).join('\n'),
        },
        ...event.content,
      ],
    };
  });

  pi.on('turn_end', () => {
    repairNotesByToolCallId.clear();
  });

  pi.on('session_start', (_event, ctx) => {
    repairNotesByToolCallId.clear();
    schemasByToolName.clear();

    const builtins = new Set(
      pi
        .getAllTools()
        .filter((tool) => tool.sourceInfo.source === 'builtin')
        .map((tool) => tool.name),
    );

    const register = <T extends RepairableDefinition>(definition: T): void => {
      if (!isBuiltinToolName(definition.name) || !builtins.has(definition.name)) return;

      const schema = normalizeRepairSchema(definition.parameters);
      if (!schema) return;

      schemasByToolName.set(definition.name, schema);
      pi.registerTool(withRepair(definition, schema));
    };

    register(createReadToolDefinition(ctx.cwd));
    register(createBashToolDefinition(ctx.cwd));
    register(createEditToolDefinition(ctx.cwd));
    register(createWriteToolDefinition(ctx.cwd));
    register(createGrepToolDefinition(ctx.cwd));
    register(createFindToolDefinition(ctx.cwd));
    register(createLsToolDefinition(ctx.cwd));
  });
}
