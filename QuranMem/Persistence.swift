import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    // Loaded once so multiple containers (e.g. in-memory stores in tests) share the same
    // entity descriptions instead of registering duplicate NSManagedObject subclasses.
    private static let model: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "QuranMem", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Failed to load Core Data model")
        }
        return model
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "QuranMem", managedObjectModel: Self.model)

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        initializeDataIfNeeded()
    }

    private func initializeDataIfNeeded() {
        let context = container.viewContext

        let fetchRequest: NSFetchRequest<SurahEntity> = SurahEntity.fetchRequest()
        fetchRequest.fetchLimit = 1

        do {
            let count = try context.count(for: fetchRequest)
            if count == 0 {
                loadSurahsFromJSON(context: context)
                initializeStats(context: context)
            } else {
                syncSurahsFromJSON(context: context)
            }
        } catch {
            print("Error checking surah count: \(error)")
        }
    }

    private func decodeSurahs() -> [Surah]? {
        guard let url = Bundle.main.url(forResource: "surahs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let surahs = try? JSONDecoder().decode([Surah].self, from: data) else {
            print("Failed to load surahs.json")
            return nil
        }
        return surahs
    }

    private func apply(_ surah: Surah, to entity: SurahEntity) {
        entity.id = Int16(surah.id)
        entity.arabicName = surah.arabicName
        entity.englishName = surah.englishName
        entity.transliteration = surah.transliteration
        entity.verseCount = Int16(surah.verseCount)
        entity.pageStart = Int16(surah.pageStart)
        entity.pageEnd = Int16(surah.pageEnd)
        entity.revelation = surah.revelation
    }

    private func loadSurahsFromJSON(context: NSManagedObjectContext) {
        guard let surahs = decodeSurahs() else { return }

        for surah in surahs {
            apply(surah, to: SurahEntity(context: context))
        }

        do {
            try context.save()
            print("Successfully loaded \(surahs.count) surahs")
        } catch {
            print("Error saving surahs: \(error)")
        }
    }

    /// Surahs are copied into Core Data on first launch, so corrections to surahs.json
    /// would never reach existing installs without this.
    private func syncSurahsFromJSON(context: NSManagedObjectContext) {
        guard let surahs = decodeSurahs() else { return }

        do {
            let entities = try context.fetch(SurahEntity.fetchRequest())
            let entitiesById = Dictionary(entities.map { (Int($0.id), $0) }, uniquingKeysWith: { first, _ in first })

            for surah in surahs {
                let entity = entitiesById[surah.id] ?? SurahEntity(context: context)
                if entity.isInserted || entity.toStruct() != surah {
                    apply(surah, to: entity)
                }
            }

            if context.hasChanges {
                try context.save()
            }
        } catch {
            print("Error syncing surahs: \(error)")
        }
    }

    private func initializeStats(context: NSManagedObjectContext) {
        let stats = StatsEntity(context: context)
        stats.id = UUID()
        stats.currentStreak = 0
        stats.longestStreak = 0
        stats.totalSessions = 0
        stats.averageRating = 0.0
        stats.updatedAt = Date()

        do {
            try context.save()
            print("Initialized user stats")
        } catch {
            print("Error initializing stats: \(error)")
        }
    }
}
