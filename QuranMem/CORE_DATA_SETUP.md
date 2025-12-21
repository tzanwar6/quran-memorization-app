# Core Data Model Setup Guide

This document explains how to configure the Core Data model in Xcode for QuranMem.

## Step-by-Step Instructions

### 1. Open Core Data Model File

1. In Xcode, locate and open `QuranMem.xcdatamodeld` in your project navigator
2. Delete the default `Item` entity if it exists

### 2. Create Entity: SurahEntity

1. Click the "Add Entity" button at the bottom
2. Rename it to `SurahEntity`
3. Add the following attributes:

| Attribute | Type | Optional |
|-----------|------|----------|
| id | Integer 16 | No |
| arabicName | String | No |
| englishName | String | No |
| transliteration | String | No |
| verseCount | Integer 16 | No |
| pageStart | Integer 16 | No |
| pageEnd | Integer 16 | No |
| revelation | String | No |

### 3. Create Entity: ScheduleEntity

1. Add new entity named `ScheduleEntity`
2. Add the following attributes:

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| id | UUID | No | - |
| surahId | Integer 16 | No | - |
| frequency | String | No | - |
| isFullSurah | Boolean | No | YES |
| startPage | Integer 16 | Yes | 0 |
| endPage | Integer 16 | Yes | 0 |
| nextDueDate | Date | No | - |
| isActive | Boolean | No | YES |
| createdAt | Date | No | - |
| updatedAt | Date | No | - |

### 4. Create Entity: SessionEntity

1. Add new entity named `SessionEntity`
2. Add the following attributes:

| Attribute | Type | Optional |
|-----------|------|----------|
| id | UUID | No |
| scheduleId | UUID | No |
| performanceRating | String | No |
| completedAt | Date | No |
| notes | String | Yes |

### 5. Create Entity: StatsEntity

1. Add new entity named `StatsEntity`
2. Add the following attributes:

| Attribute | Type | Optional | Default |
|-----------|------|----------|---------|
| id | UUID | No | - |
| currentStreak | Integer 16 | No | 0 |
| longestStreak | Integer 16 | No | 0 |
| totalSessions | Integer 16 | No | 0 |
| averageRating | Double | No | 0.0 |
| lastSessionDate | Date | Yes | - |
| updatedAt | Date | No | - |

## Setting Attribute Properties

For each attribute:
1. Select the attribute in the model editor
2. In the Data Model Inspector (right panel):
   - Set **Type** as specified above
   - Uncheck **Optional** for non-optional fields
   - Set **Default Value** if specified

## Important Notes

### Index Configuration (Optional but Recommended)

To improve query performance, add indexes:

**For SurahEntity:**
- Index on: `id`

**For ScheduleEntity:**
- Index on: `surahId`
- Index on: `nextDueDate`
- Index on: `isActive`

**For SessionEntity:**
- Index on: `scheduleId`
- Index on: `completedAt`

To add an index:
1. Select the entity
2. In the Data Model Inspector, scroll to "Indexes"
3. Click "+" to add index
4. Add the attribute name

### Codegen Settings

For each entity, set the Codegen setting:
1. Select the entity
2. In Data Model Inspector, find "Codegen"
3. Set to **"Class Definition"**

This allows Xcode to auto-generate the entity classes.

## Verification

After setup, your Core Data model should have:
- ✅ 4 entities (SurahEntity, ScheduleEntity, SessionEntity, StatsEntity)
- ✅ All attributes with correct types
- ✅ Proper optional/required settings
- ✅ Codegen set to "Class Definition"

## Next Steps

After configuring the Core Data model:
1. Build the project (Cmd+B) to generate entity classes
2. The entities will automatically work with the provided Swift code
3. Data will be initialized on first app launch

## Troubleshooting

**If you see build errors after setup:**
- Clean Build Folder (Cmd+Shift+K)
- Build again (Cmd+B)

**If data isn't loading:**
- Check that `surahs.json` is added to your target
- Verify the JSON file is in the project bundle

**To reset the database during development:**
- Delete the app from simulator/device
- Run again for a fresh database
