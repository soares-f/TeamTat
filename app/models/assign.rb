class Assign < ApplicationRecord
  belongs_to :project, counter_cache: true
  belongs_to :user
  belongs_to :project_user
  belongs_to :document, counter_cache: true
  has_many :annotations
  has_many :relations

  def init_review_result
    version = self.document.version
    prev_annotations = self.document.annotations.where("version = ?", version - 1).order('offset ASC, content ASC').all
    annotations = self.annotations.where("version = ?", version).order('offset ASC, content ASC').all
    agreed = []
    annotations.each do |a|
      same_annotations = prev_annotations.select{|p| p.offset == a.offset && p.content == a.content && p.a_type == a.a_type && p.concept == a.concept}
      if same_annotations.size == self.document.assigns.size || self.project.collaborates[version - 1]
        agreed << a.id
      end
    end
    Annotation.execute_sql("UPDATE annotations SET review_result = 1 WHERE id IN (?) ", agreed);
  end

  def copy_previous_versions
    ref_id_map = {}

    Assign.transaction do    
      insert_values = []
      max_id = self.document.annotations.where('version=?', self.document.version).maximum('a_id_no') || 0;
      a_id_no = max_id
      self.document.annotations.where('version=?', self.document.version - 1).each do |a|
        a_id_no += 1
        ref_id_map[a.a_id] = "#{a_id_no}"
        annotation = self.document.annotations.create!({
          a_id: a_id_no,
          a_id_no: a_id_no,
          a_type: a.a_type, 
          concept: a.concept,
          assign_id: self.id,
          user_id: self.user_id,
          content: a.content,
          note: a.note,
          offset: a.offset,
          passage: a.passage,
          annotator: a.annotator,
          project_id: self.project_id,
          version: self.document.version,
          infons: a.infons,
          review_result: 0,
          created_at: a.created_at,
          updated_at: a.updated_at
        });
      end

      if self.project.round > 0
        self.init_review_result
      end
      Rails.logger.debug(ref_id_map.inspect)
      max_id = self.document.relations.where('version=?', self.document.version).maximum('r_id_no') || 0;
      r_id_no = max_id
      self.document.relations.where('version=?', self.document.version - 1).each do |r|
        r_id_no += 1
        ref_id_map[r.r_id] = "R#{r_id_no}"
        relation = self.document.relations.create!({
          r_id: "R#{r_id_no}",
          r_id_no: r_id_no,
          r_type: r.r_type, 
          assign_id: self.id,
          user_id: self.user_id,
          note: r.note,
          annotator: r.annotator,
          version: self.document.version,
          infons: r.infons,
          created_at: r.created_at,
          updated_at: r.updated_at,
          sig1: r.sig1,
          sig2: r.sig2
        });

        r.nodes.each do |n|
          relation.nodes.create!({
            document_id: self.document.id,
            version: self.document.version,
            order_no: n.order_no,
            role: n.role,
            ref_id: ref_id_map[n.ref_id] || n.ref_id
          })
        end
      end


      # Assign.reset_counters(self.id, :annotation)
      # Annotation.execute_sql("   
      #   INSERT INTO annotations(
      #     a_id, a_id_no, a_type, concept,  
      #     user_id, content, note, offset, passage, 
      #     document_id, annotator, version, infons,
      #     assign_id, created_at, updated_at
      #   ) 
      #   SELECT 
      #     a_id, a_id_no, a_type, concept, 
      #     #{self.user.id}, content, note, offset, passage, 
      #     document_id, 
      #     annotator,
      #     (version + 1), infons,
      #     #{self.id}, created_at, updated_at
      #   FROM annotations
      #   WHERE 
      #     document_id = ? AND
      #     version = ?
      #   ", self.document_id, self.document.version - 1
      # )
      self.detached = true
      self.begin_at = Time.now
      self.save
    end
  end
end
