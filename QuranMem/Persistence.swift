import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "QuranMem")
        
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
            }
        } catch {
            print("Error checking surah count: \(error)")
        }
    }
    
    private func loadSurahsFromJSON(context: NSManagedObjectContext) {
        guard let url = Bundle.main.url(forResource: "surahs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let surahs = try? JSONDecoder().decode([Surah].self, from: data) else {
            print("Failed to load surahs.json")
            return
        }
        
        for surah in surahs {
            let entity = SurahEntity(context: context)
            entity.id = Int16(surah.id)
            entity.arabicName = surah.arabicName
            entity.englishName = surah.englishName
            entity.transliteration = surah.transliteration
            entity.verseCount = Int16(surah.verseCount)
            entity.pageStart = Int16(surah.pageStart)
            entity.pageEnd = Int16(surah.pageEnd)
            entity.revelation = surah.revelation
        }
        
        do {
            try context.save()
            print("Successfully loaded \(surahs.count) surahs")
        } catch {
            print("Error saving surahs: \(error)")
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
